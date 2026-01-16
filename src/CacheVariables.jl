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

!!! note

    Since this macro wraps the provided code into a function to pass to [`cache`](@ref),
    the relevant scoping rules apply. This can produce potentially suprising behavior,
    e.g., with `let` blocks. See the examples below.

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

julia> @cache "test-with-let.bson" begin
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           let
               c = "this will not be cached"
               b = "this will overwrite the variable b"
           end
           let
               local b = "this will not overwrite b"
           end
           100
       end
[ Info: Variable assignments found: a, b
┌ Info: Saved cached values to test-with-let.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
100

julia> a, b    # b was overwritten in the first let block but not the second
("a very time-consuming quantity to compute", "this will overwrite the variable b")
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
    varsinfo =
        isempty(varnames) ? "No variable assignments found" :
        "Variable assignments found: $(join(varnames, ", "))"

    # Create the caching code
    return quote
        # Output @info log about variable assignments found
        @info $varsinfo

        # Run the code and cache the identified variables
        result = cache($(esc(path)); $(esc.(kwargs)...)) do
            ans = $(esc(block))
            return (; vars = (; $(esc.(varnames)...)), ans)
        end

        # Assign the identified variables
        (; $(esc.(varnames)...)) = result.vars

        # Output final result of the code
        result.ans
    end
end

"""
    cache(f, path; overwrite=false, bson_mod=Main)

Cache the output of running `f()` in a cache file at `path`.
The output is loaded if the file exists and is saved otherwise.

In addition to the output of `f()`, the following metadata is saved for the run:
- Julia version
- Time when run (in UTC)
- Runtime of code (in seconds)

If `path` is set to `nothing`, caching is disabled and `f()` is simply run.
This can be useful for conditionally caching the results,
e.g., to only cache a sweep when the full set is ready.
If `overwrite` is set to true, existing cache files will be overwritten
with the results (and metadata) from a "fresh" call to `f()`.
If necessary, the module to use for BSON can be set with `bson_mod`.

Tip: Use a `do...end` block to cache the results of a block of code.

# Examples
```julia-repl
julia> cache("test.bson") do
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           return (; a = a, b = b)
       end
┌ Info: Saved cached values to test.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> cache("test.bson") do
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           return (; a = a, b = b)
       end
┌ Info: Loaded cached values from test.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> cache(nothing) do
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           return (; a = a, b = b)
       end
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```
"""
function cache(@nospecialize(f), path; overwrite = false, bson_mod = Main)
    if isnothing(path)
        return f()
    elseif !ispath(path) || overwrite
        # Collect metadata and run function
        version = VERSION
        whenrun = Dates.now(Dates.UTC)
        runtime = @elapsed output = f()

        # Log @info message
        main_msg =
            ispath(path) ? "Overwrote $path with cached values." :
            "Saved cached values to $path."
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
