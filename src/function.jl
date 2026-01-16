# Function form

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
        whenrun = now(UTC)
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
