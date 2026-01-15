module CacheVariables

using BSON
import Dates
import Logging: @info
using MacroTools: @capture
using ExpressionExplorer: compute_symbols_state

export @cache, cache

"""
    @cache path begin ... end [overwrite=true, bson_mod=@__MODULE__]

Cache the variables assigned in the `begin...end` block as well as the final result.
Cached values are loaded if the file exists; the code is run and values are saved if not.
Internally, this simply creates a call to [`cache`](@ref) - see those docs for more info.

Tip: Use the function form [`cache`](@ref) directly to only cache the final result.

!!! warning

    This macro works by parsing the block to identify which variables have been assigned in it.
    This should generally work, but may not always catch all the variables - check the list
    printed out to make sure. The function form [`cache`](@ref) can be used for more control.

See also: [`cache`](@ref)

# Examples
```julia-repl
julia> @cache "test.bson" begin
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           100
       end
[ Info: Variable assignments found: a, b
┌ Info: Saved cached values to test.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
100

julia> @cache "test.bson" begin
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           100
       end
[ Info: Variable assignments found: a, b
┌ Info: Loaded cached values from test.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
100
```
"""
macro cache(path, expr, kwexprs...)
    if expr.head === :block    # begin...end blocks
        _cache_block(__module__, path, expr, kwexprs...)
    else
        throw(ArgumentError("@cache currently only supports `begin...end` blocks."))
    end
end

function _cache_block(mod, path, block, kwexprs...)
    # Process keyword arguments
    kwdict = Dict(:overwrite => false, :bson_mod => :(@__MODULE__))
    for expr in kwexprs
        if @capture(expr, lhs_ = rhs_) && haskey(kwdict, lhs)
            kwdict[lhs] = rhs
        elseif haskey(kwdict, expr)
            kwdict[expr] = expr
        else
            throw(ArgumentError("Unsupported optional argument: $expr"))
        end
    end
    kwargs = [Expr(:kw, key, val) for (key, val) in kwdict]

    # Identify assigned variables and construct @info string
    expblock = macroexpand(mod, block)
    varnames = sort(collect(compute_symbols_state(expblock).assignments))
    varsinfo = isempty(varnames) ?
               "No variable assignments found" :
               "Variable assignments found: $(join(varnames, ", "))"

    # Create the caching code
    return quote
        # Output @info log about variable assignments found
        @info $varsinfo

        # Run the code and cache the identified variables
        result = cache($(esc(path)); $(esc.(kwargs)...)) do
            ans = $(esc(block))
            return (; vars=(; $(esc.(varnames)...)), ans)
        end

        # Assign the identified variables
        (; $(esc.(varnames)...)) = result.vars

        # Output final result of the code
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
