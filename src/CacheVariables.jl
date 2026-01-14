module CacheVariables

using BSON
import Dates
import Logging: @info

export @cache, cache, barecache

function _cachevars(ex::Expr)
    (ex.head === :(=)) && return Symbol[ex.args[1]]
    (ex.head === :block) && return collect(Iterators.flatten([
        _cachevars(exi) for exi in ex.args if isa(exi, Expr)
    ]))
    return Vector{Symbol}(undef, 0)
end

"""
    @cache path code [overwrite]

Transform code to use the `cache` function interface with automatic variable handling.

For `begin...end` blocks, the macro:
- Identifies variables assigned in the block
- Transforms the block to return a named tuple with those variables
- Wraps it in a `cache` call
- Destructures the result back into the original variables

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
"""
macro cache(path, ex::Expr, overwrite = false)
    # Check if this is a map expression
    if ex.head === :call && length(ex.args) >= 2 && ex.args[1] === :map
        # Handle map case: @cache "path" map(iter) do i ... end
        return _cache_map(path, ex, overwrite, __module__)
    else
        # Handle begin...end block case
        return _cache_block(path, ex, overwrite, __module__)
    end
end

function _cache_block(path, ex::Expr, overwrite, mod)
    vars = _cachevars(ex)
    
    # Build the named tuple constructor for the variables
    varkws = [Expr(:kw, var, esc(var)) for var in vars]
    
    # Build the named tuple for destructuring
    if isempty(vars)
        # If no variables, just return ans
        return quote
            cache($(esc(path)); overwrite = $(esc(overwrite))) do
                $(esc(ex))
            end
        end
    else
        # Build destructuring - extract each variable individually from the named tuple
        var_assignments = [:($(esc(var)) = _result.$(var)) for var in vars]
        
        # Build checks for each variable
        var_checks = [:(haskey(_result, $(QuoteNode(var))) || push!(_missing, $(QuoteNode(var)))) for var in vars]
        
        return quote
            begin
                _result = cache($(esc(path)); overwrite = $(esc(overwrite))) do
                    _ans = begin
                        $(esc(ex))
                    end
                    return (; $(varkws...), ans = _ans)
                end
                # Check that all variables exist in the cache
                if _result isa NamedTuple
                    _missing = Symbol[]
                    $(var_checks...)
                    if !isempty(_missing)
                        error("Variables not found in cache file $($(esc(path))): ", join(_missing, ", "))
                    end
                end
                # Extract each variable from the result and assign to parent scope
                $(var_assignments...)
                # Return the final value
                _result.ans
            end
        end
    end
end

function _cache_map(path, ex::Expr, overwrite, mod)
    # Extract the map components
    # Pattern: map(iter) do i ... end
    # This transforms into: map(enumerate(iter)) do (iteration_index, i) 
    #                          cache(joinpath(path, "$iteration_index")) do ... end
    #                       end
    # Each iteration is cached in a separate file: path/1, path/2, etc.
    
    if length(ex.args) == 3 && Meta.isexpr(ex.args[3], :do)
        # map(iter) do i ... end
        iter_expr = ex.args[2]
        do_block = ex.args[3]
        # do_block.args[1] is the parameters (e.g., :i or Expr(:tuple, :i))
        # do_block.args[2] is the body
        
        user_params = do_block.args[1]
        body = do_block.args[2]
        
        # Use _cache_iter_idx as the iteration index to avoid conflicts with user variables
        return quote
            map(enumerate($(esc(iter_expr)))) do (_cache_iter_idx, $(esc(user_params)))
                cache(joinpath($(esc(path)), string(_cache_iter_idx)); overwrite = $(esc(overwrite))) do
                    $(esc(body))
                end
            end
        end
    else
        error("@cache with map requires the pattern: @cache \"path\" map(iter) do i ... end")
    end
end

"""
    barecache(f, path; bson_mod = @__MODULE__, overwrite = false)

Cache output from running `f()` using BSON file at `path`.
Load if the file exists; run and save if it does not.
Use `bson_mod` keyword argument to specify module.
Run and save either way if `overwrite` is true (default is false).

Tip: Use `do...end` to cache output from a block of code.

# Examples
```julia-repl
julia> barecache("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Saving to test.bson
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> barecache("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Loading from test.bson
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```
"""
function barecache(@nospecialize(f), path; bson_mod = @__MODULE__, overwrite = false)
    if !ispath(path) || overwrite
        ans = f()
        _msg = ispath(path) ? "Overwriting " : "Saving to "
        @info(string(_msg, path, "\n"))
        mkpath(splitdir(path)[1])
        bson(path; ans = ans)
        return ans
    else
        @info(string("Loading from ", path, "\n"))
        data = BSON.load(path, bson_mod)
        return data[:ans]
    end
end
function barecache(@nospecialize(f), ::Nothing; bson_mod = @__MODULE__, overwrite = false)
    @info("No path provided, running without caching.")
    return f()
end

"""
    cache(f, path; bson_mod = @__MODULE__, overwrite = false)

Cache output from running `f()` using BSON file at `path` with additional metadata.
Load if the file exists; run and save if it does not.
Use `bson_mod` keyword argument to specify module.
Run and save either way if `overwrite` is true (default is false).

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
```
"""
function cache(@nospecialize(f), path; bson_mod = @__MODULE__, overwrite = false)
    version, whenrun, runtime, ans = barecache(path; bson_mod = bson_mod, overwrite = overwrite) do
        version = VERSION
        whenrun = Dates.now(Dates.UTC)
        runtime = @elapsed ans = f()
        return (version, whenrun, runtime, ans)
    end
    @info "Run was started at $whenrun and took $runtime seconds."
    return ans
end

end # module
