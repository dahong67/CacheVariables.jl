module CacheVariables

using BSON
import Dates
import Logging: @info

export @cache, cache

function _cachevars(ex::Expr)
    (ex.head === :(=)) && return Symbol[ex.args[1]]
    (ex.head === :block) && return collect(Iterators.flatten([
        _cachevars(exi) for exi in ex.args if isa(exi, Expr)
    ]))
    return Vector{Symbol}(undef, 0)
end

"""
    @cache path begin ... end [overwrite]

Cache the variables defined in a `begin...end` block along with the final output.

The macro identifies variables assigned in the block, wraps the code in a `cache` function call,
and destructures the results back into the original variables. Metadata tracking (Julia version,
timestamp, runtime) is included automatically.

Load if the file exists; run and save if it does not.
Run and save either way if `overwrite` is true (default is false).

# Examples
```julia-repl
julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end
[ Info: Saving to test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
100

julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end
[ Info: Loading from test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
100
```

---

    @cache path map(iter) do i ... end [overwrite] [merge=true] [bson_mod=@__MODULE__]

Cache the runs of a `map` operation, with each iteration cached in a separate file.

The macro wraps each iteration in a `cache` call, using files like `basename/1.ext`, `basename/2.ext`, etc.
where the base name and extension are extracted from the provided path. If `merge` is true (default),
a merged cache file is also created at the provided path after all iterations complete.

# Examples
```julia-repl
julia> @cache "results.bson" map(1:3) do i
         # expensive computation for iteration i
         "result \$i"
       end
[ Info: Saving to results/1.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to results/2.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to results/3.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to results.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
3-element Vector{String}:
 "result 1"
 "result 2"
 "result 3"
```
"""
macro cache(path, ex::Expr, overwrite = false, merge = true, bson_mod = :(@__MODULE__))
    # Check for supported patterns
    if ex.head === :block
        # Handle begin...end block case
        return _cache_block(path, ex, overwrite, bson_mod)
    elseif ex.head === :call && length(ex.args) >= 2 && ex.args[1] === :map
        # Handle map case: @cache "path" map(iter) do i ... end
        return _cache_map(path, ex, overwrite, bson_mod, merge)
    elseif ex.head === :comprehension || ex.head === :generator
        # Handle comprehension: @cache "path" [f(i) for i in iter]
        error("@cache does not yet support comprehensions. Use map form instead.")
    else
        # Wrap other expressions in a block and process
        wrapped_ex = Expr(:block, ex)
        return _cache_block(path, wrapped_ex, overwrite, bson_mod)
    end
end

function _cache_block(path, ex::Expr, overwrite, bson_mod)
    vars = _cachevars(ex)
    
    # Build the named tuple constructor for the variables
    varkws = [Expr(:kw, var, esc(var)) for var in vars]
    
    # Use gensym for macro hygiene
    result_sym = gensym(:result)
    ans_sym = gensym(:ans)
    
    return quote
        begin
            $(esc(result_sym)) = cache($(esc(path)); bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                $(esc(ans_sym)) = $(esc(ex))
                return (; vars = (; $(varkws...)), ans = $(esc(ans_sym)))
            end
            # Extract variables
            (; $(esc.(vars)...),) = $(esc(result_sym)).vars
            # Return the final value
            $(esc(result_sym)).ans
        end
    end
end

function _cache_map(path, ex::Expr, overwrite, bson_mod, merge_cache = true)
    # Extract the map components
    # Pattern 1: map(iter) do i ... end
    # Pattern 2: map(func, args...)
    # This transforms into: map(enumerate(iter)) do (iteration_index, i) 
    #                          cache(joinpath(basepath, "$(iteration_index).ext")) do ... end
    #                       end
    # Each iteration is cached in a separate file with proper extension handling.
    
    if length(ex.args) == 3 && Meta.isexpr(ex.args[3], :do)
        # Pattern 1: map(iter) do i ... end
        iter_expr = ex.args[2]
        do_block = ex.args[3]
        user_params = do_block.args[1]
        body = do_block.args[2]
        
        # Use gensym for macro hygiene
        iter_idx_sym = gensym(:cache_iter_idx)
        
        return quote
            let _path_str = $(esc(path))
                _base, _ext = splitext(_path_str)
                _results = map(enumerate($(esc(iter_expr)))) do ($(esc(iter_idx_sym)), $(esc(user_params)))
                    cache(string(_base, "/", $(esc(iter_idx_sym)), _ext); bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                        $(esc(body))
                    end
                end
                # Create merged cache if requested
                if $(esc(merge_cache))
                    cache(_path_str; bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                        _results
                    end
                else
                    _results
                end
            end
        end
    elseif length(ex.args) >= 3
        # Pattern 2: map(func, args...)
        func_expr = ex.args[2]
        args_exprs = ex.args[3:end]
        
        # Use gensym for macro hygiene
        iter_idx_sym = gensym(:cache_iter_idx)
        elem_sym = gensym(:elem)
        
        # For multiple arguments, we need to zip them
        if length(args_exprs) == 1
            iter_expr = args_exprs[1]
            return quote
                let _path_str = $(esc(path))
                    _base, _ext = splitext(_path_str)
                    _results = map(enumerate($(esc(iter_expr)))) do ($(esc(iter_idx_sym)), $(esc(elem_sym)))
                        cache(string(_base, "/", $(esc(iter_idx_sym)), _ext); bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                            $(esc(func_expr))($(esc(elem_sym)))
                        end
                    end
                    # Create merged cache if requested
                    if $(esc(merge_cache))
                        cache(_path_str; bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                            _results
                        end
                    else
                        _results
                    end
                end
            end
        else
            # Multiple arguments - use zip
            return quote
                let _path_str = $(esc(path))
                    _base, _ext = splitext(_path_str)
                    _results = map(enumerate(zip($(esc.(args_exprs)...),))) do ($(esc(iter_idx_sym)), $(esc(elem_sym)))
                        cache(string(_base, "/", $(esc(iter_idx_sym)), _ext); bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                            $(esc(func_expr))($(esc(elem_sym))...)
                        end
                    end
                    # Create merged cache if requested
                    if $(esc(merge_cache))
                        cache(_path_str; bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                            _results
                        end
                    else
                        _results
                    end
                end
            end
        end
    else
        error("@cache with map requires the pattern: @cache \"path\" map(iter) do i ... end or @cache \"path\" map(func, args...)")
    end
end

"""
    cache(f, path; bson_mod = @__MODULE__, overwrite = false)

Cache output from running `f()` using BSON file at `path` with additional metadata.
Load if the file exists; run and save if it does not.
Use `bson_mod` keyword argument to specify module.
Run and save either way if `overwrite` is true (default is false).

If the path is set to `nothing`, then caching is skipped and the function is simply run.

Saves and displays the following metadata:
- Julia version (from `VERSION`)
- Time when run (from `Dates.now(Dates.UTC)`)
- Runtime of code (in seconds)

Tip: Use `do...end` to cache output from a block of code.

# Examples
```julia-repl
julia> cache("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Saving to test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> cache("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Loading from test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> cache(nothing) do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: No path provided, running without caching.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```
"""
function cache(@nospecialize(f), path; bson_mod = @__MODULE__, overwrite = false)
    if isnothing(path)
        @info("No path provided, running without caching.")
        return f()
    elseif !ispath(path) || overwrite
        # Run and cache with metadata
        version = VERSION
        whenrun = Dates.now(Dates.UTC)
        runtime = @elapsed val = f()
        _msg = ispath(path) ? "Overwriting " : "Saving to "
        @info(string(_msg, path, "\n"))
        mkpath(splitdir(path)[1])
        bson(path; version = version, whenrun = whenrun, runtime = runtime, val = val)
        @info "Run was started at $whenrun and took $runtime seconds."
        return val
    else
        # Load from cache with info messages including the metadata
        @info(string("Loading from ", path, "\n"))
        data = BSON.load(path, bson_mod)
        version = data[:version]
        whenrun = data[:whenrun]
        runtime = data[:runtime]
        @info "Run was started at $whenrun and took $runtime seconds."
        return data[:val]
    end
end

end # module
