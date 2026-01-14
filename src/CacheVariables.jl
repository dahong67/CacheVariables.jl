module CacheVariables

using BSON
import Dates
import Logging: @info
using MacroTools: @capture

export @cache, cache

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
macro cache(path, expr, kwexprs...)
    # Dispatch to correct method
    if expr.head === :block
        _cache_block(path, expr, kwexprs...)
    else
        throw(ArgumentError("@cache currently only supports `begin ... end` blocks."))
    end
end

function _cache_block(path, body, kwexprs...)
    # Process keyword arguments
    kwdict = Dict(:overwrite => false, :bson_mod => :(@__MODULE__))
    for expr in kwexprs
        if @capture(expr, lhs_ = rhs_) && haskey(kwdict, lhs)
            kwdict[lhs] = rhs
        else
            throw(ArgumentError("Unsupported optional argument: $expr"))
        end
    end

    # Process body and extract variable names
    @capture(body, begin
        lines__
    end) || throw(ArgumentError("`begin ... end` block not found"))
    varnames = Symbol[]
    for line in lines
        if @capture(line, lhs_Symbol = rhs_)
            push!(varnames, lhs)
        elseif @capture(line, (; lhs__,) = rhs_)
            append!(varnames, lhs)
        elseif @capture(line, (lhs__,) = rhs_)
            append!(varnames, lhs)
        end
    end
    unique!(varnames)

    # Create @info string
    varinfostring = "@cache identified the variables: $(join(varnames, ", "))"

    # Create cache block
    return quote
        # Info string
        @info $varinfostring

        # Run expression and cache identified variables
        result = cache($(esc(path)); overwrite=$(esc(kwdict[:overwrite])), bson_mod=$(esc(kwdict[:bson_mod]))) do
            ans = $(esc(body))
            return (; vars=(; $(esc.(varnames)...)), ans)
        end

        # Assign identified variables
        (; $(esc.(varnames)...)) = result.vars

        # Final output
        result.ans
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
    @show bson_mod
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
