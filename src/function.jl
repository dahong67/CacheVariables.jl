# Function form

# Helper function to validate file extensions
function _validate_extension(path)
    if !endswith(path, ".bson") && !endswith(path, ".jld2")
        error("Unsupported file extension for $path. Only .bson and .jld2 are supported.")
    end
end

"""
    cache(f, path; overwrite=false, bson_mod=Main)

Cache the output of running `f()` in a cache file at `path`.
The output is loaded if the file exists and is saved otherwise.

The file format is determined by the file extension:
`.bson` for [BSON.jl](https://github.com/JuliaIO/BSON.jl) and
`.jld2` for [JLD2.jl](https://github.com/JuliaIO/JLD2.jl).

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
        # Validate file extension early
        _validate_extension(path)

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
        if endswith(path, ".bson")
            bson(path; version, whenrun, runtime, output)
        else  # .jld2
            JLD2.jldsave(path; version, whenrun, runtime, output)
        end
        return output
    else
        # Validate file extension early
        _validate_extension(path)

        # Load metadata and output
        if endswith(path, ".bson")
            (; version, whenrun, runtime, output) = NamedTuple(BSON.load(path, bson_mod))
        else  # .jld2
            data = JLD2.load(path)
            version = data["version"]
            whenrun = data["whenrun"]
            runtime = data["runtime"]
            output = data["output"]
        end

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
