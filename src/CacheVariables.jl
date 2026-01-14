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
    @cache path begin ... end
    @cache path map(...)
    @cache path [... for ... in ...]

Cache the variables defined in a `begin...end` block, the runs of a `map`, 
or the elements of a comprehension. Metadata tracking (Julia version, timestamp, 
runtime) is included automatically.

For blocks, variables assigned in the block are cached along with the final output.
For maps and comprehensions, each iteration is cached in a separate file.

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

julia> @cache "results.bson" map(1:3) do i
         "result \$i"
       end
[ Info: Saving to results/1.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
...
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
        return _cache_comprehension(path, ex, overwrite, bson_mod, merge)
    else
        error("@cache only supports begin...end blocks, map expressions, and comprehensions. Got: $(ex.head)")
    end
end

function _cache_block(path, ex::Expr, overwrite, bson_mod)
    vars = _cachevars(ex)
    
    # Build the named tuple constructor for the variables
    varkws = [Expr(:kw, var, esc(var)) for var in vars]
    
    return quote
        begin
            result = cache($(esc(path)); bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                ans = $(esc(ex))
                return (; vars = (; $(varkws...)), ans = ans)
            end
            # Extract variables
            (; $(esc.(vars)...),) = result.vars
            # Return the final value
            result.ans
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
        
        return quote
            let _path_str = $(esc(path))
                _base, _ext = splitext(_path_str)
                _results = map(enumerate($(esc(iter_expr)))) do (cache_iter_idx, $(esc(user_params)))
                    cache(joinpath(_base, string(cache_iter_idx, _ext)); bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                        $(esc(body))
                    end
                end
                # Create merged cache if requested
                cache($(esc(merge_cache)) ? _path_str : nothing; bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                    _results
                end
            end
        end
    elseif length(ex.args) >= 3
        # Pattern 2: map(func, args...)
        func_expr = ex.args[2]
        args_exprs = ex.args[3:end]
        
        # For multiple arguments, we need to zip them
        if length(args_exprs) == 1
            iter_expr = args_exprs[1]
            return quote
                let _path_str = $(esc(path))
                    _base, _ext = splitext(_path_str)
                    _results = map(enumerate($(esc(iter_expr)))) do (cache_iter_idx, elem)
                        cache(joinpath(_base, string(cache_iter_idx, _ext)); bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                            $(esc(func_expr))(elem)
                        end
                    end
                    # Create merged cache if requested
                    cache($(esc(merge_cache)) ? _path_str : nothing; bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                        _results
                    end
                end
            end
        else
            # Multiple arguments - use zip
            return quote
                let _path_str = $(esc(path))
                    _base, _ext = splitext(_path_str)
                    _results = map(enumerate(zip($(esc.(args_exprs)...),))) do (cache_iter_idx, elem)
                        cache(joinpath(_base, string(cache_iter_idx, _ext)); bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                            $(esc(func_expr))(elem...)
                        end
                    end
                    # Create merged cache if requested
                    cache($(esc(merge_cache)) ? _path_str : nothing; bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                        _results
                    end
                end
            end
        end
    else
        error("@cache with map requires the pattern: @cache \"path\" map(iter) do i ... end or @cache \"path\" map(func, args...)")
    end
end

function _cache_comprehension(path, ex::Expr, overwrite, bson_mod, merge_cache = true)
    # Handle comprehension: [f(i) for i in iter]
    # Transform to: map(enumerate(iter)) do (idx, i) cache(...) do f(i) end end
    
    # ex is either :comprehension or :generator
    # For comprehension: ex.args[1] is the generator expression
    # Generator has form: Expr(:generator, body, iteration_spec)
    
    if ex.head === :comprehension
        gen = ex.args[1]
    else
        gen = ex
    end
    
    if !Meta.isexpr(gen, :generator)
        error("Unexpected comprehension structure")
    end
    
    body = gen.args[1]
    iter_spec = gen.args[2]
    
    # iter_spec is like :(i = iter)
    if !Meta.isexpr(iter_spec, :(=))
        error("Unsupported comprehension iteration pattern")
    end
    
    var = iter_spec.args[1]
    iter_expr = iter_spec.args[2]
    
    return quote
        let _path_str = $(esc(path))
            _base, _ext = splitext(_path_str)
            _results = [begin
                cache(joinpath(_base, string(cache_iter_idx, _ext)); bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                    $(esc(body))
                end
            end for (cache_iter_idx, $(esc(var))) in enumerate($(esc(iter_expr)))]
            # Create merged cache if requested
            cache($(esc(merge_cache)) ? _path_str : nothing; bson_mod = $(esc(bson_mod)), overwrite = $(esc(overwrite))) do
                _results
            end
        end
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
        @info string(_msg, path, "\nRun was started at ", whenrun, " and took ", runtime, " seconds.")
        mkpath(splitdir(path)[1])
        bson(path; version = version, whenrun = whenrun, runtime = runtime, val = val)
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
