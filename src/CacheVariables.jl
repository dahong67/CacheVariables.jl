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

Cache the variables defined in a `begin...end` block along with the final output.
Metadata tracking (Julia version, timestamp, runtime) is included automatically.

Variables assigned in the block are cached along with the final output value.
Load if the file exists; run and save if it does not.

# Examples
```julia-repl
julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end
[ Info: Saving cached values to test.bson.
  Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
  Julia Version : 1.10.0
100

julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end
[ Info: Loaded cached values from test.bson.
  Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
  Julia Version : 1.10.0
100
```
"""
macro cache(path, ex::Expr, overwrite = false, bson_mod = :(@__MODULE__))
    # Check for supported patterns
    if ex.head === :block
        # Handle begin...end block case
        return _cache_block(path, ex, overwrite, bson_mod)
    elseif ex.head === :call && length(ex.args) >= 2 && ex.args[1] === :map
        # Map support left for future PRs
        error("@cache does not yet support map expressions. Use the `cache` function directly for now.")
    elseif ex.head === :comprehension || ex.head === :generator
        # Comprehension support left for future PRs
        error("@cache does not yet support comprehensions. Use the `cache` function directly for now.")
    else
        error("@cache only supports begin...end blocks. Got: $(ex.head)")
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
function cache(@nospecialize(f), path; bson_mod=@__MODULE__, overwrite=false)
    if isnothing(path)
        @info "No cachefile provided - running without caching."
        return f()
    elseif !ispath(path) || overwrite
        # Collect metadata and run function
        version = VERSION
        whenrun = Dates.now(Dates.UTC)
        runtime = @elapsed output = f()

        # Log @info message
        main_msg = ispath(path) ? "Overwriting $path with cached values." : "Saving cached values to $path."
        @info """
        $main_msg
          Run Timestamp : $whenrun UTC (run took $runtime sec)
          Julia Version : $version
        """

        # Save metadata and output
        mkpath(dirname(path))
        bson(path; version, whenrun, runtime, output)
        return output
    else
        # Load metadata and output
        (; version, whenrun, runtime, output) = NamedTuple(BSON.load(path, bson_mod))

        # Log @info message
        @info """
        Loaded cached values from $path.
          Run Timestamp : $whenrun UTC (run took $runtime sec)
          Julia Version : $version
        """

        # Return output
        return output
    end
end

end # module
