# Function form

"""
    cache(f, path; overwrite=false, verbose=true)

Cache the output of running `f()` in a cache file at `path`.
The output is loaded if the file exists and is saved otherwise.

In addition to the output of `f()`, the following metadata is saved for the run:
- Julia version
- Time when run (in UTC)
- Runtime of code (in seconds)

The file extension of `path` determines the file format used:
`.bson` for [BSON.jl](https://github.com/JuliaIO/BSON.jl) and
`.jld2` for [JLD2.jl](https://github.com/JuliaIO/JLD2.jl).
The `path` can also be set to `nothing` to disable caching and simply run `f()`.
This can be useful for conditionally caching the results,
e.g., to only cache a sweep when the full set is ready.

If `overwrite` is set to true, existing cache files will be overwritten
with the results (and metadata) from a "fresh" call to `f()`.

If `verbose` is set to false, log messages will be suppressed.

Tip: Use a `do...end` block to cache the results of a block of code.

See also: [`cached`](@ref)

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
function cache(@nospecialize(f), path; overwrite = false, verbose = true)
    # Call cached
    (; value, version, whenrun, runtime, status) = cached(f, path; overwrite)

    # Emit log message
    if verbose && status !== :disabled
        logmsg = if status === :saved
            "Saved cached values to $path."
        elseif status === :loaded
            "Loaded cached values from $path."
        elseif status === :overwrote
            "Overwrote $path with cached values."
        end
        @info """
        $logmsg
          Run Timestamp : $whenrun UTC (run took $runtime sec)
          Julia Version : $version
        """
    end

    # Return output
    return value
end

"""
    cached(f, path; overwrite=false)

Cache the output of running `f()` in a cache file at `path`
and return the output and metadata as a `NamedTuple`.
The output and metadata are loaded if the file exists and are saved otherwise.

The returned `NamedTuple` has the following fields:
- `value`   : the output of running `f()`.
- `version` : the Julia version used when the code was run.
- `whenrun` : the timestamp when the code was run (in UTC).
- `runtime` : the runtime of the code (in seconds).
- `status`  : status flag indicating if the results were saved / loaded / etc.
              (possible values are `:saved`, `:loaded`, `:overwrote`, `:disabled`)

The file extension of `path` determines the file format used:
`.bson` for [BSON.jl](https://github.com/JuliaIO/BSON.jl) and
`.jld2` for [JLD2.jl](https://github.com/JuliaIO/JLD2.jl).
The `path` can also be set to `nothing` to disable caching and simply run `f()`.
This can be useful for conditionally caching the results,
e.g., to only cache a sweep when the full set is ready.

If `overwrite` is set to true, existing cache files will be overwritten
with the results (and metadata) from a "fresh" call to `f()`.

Tip: Use a `do...end` block to cache the results of a block of code.

See also: [`cache`](@ref)

# Examples
```julia-repl
julia> result = cached("test.bson") do
           return "output"
       end
(value = "output", \
version = v"1.11.8", \
whenrun = Dates.DateTime("2024-01-01T00:00:00.000"), \
runtime = 0.123, \
status = :saved)

julia> result.value
"output"

julia> result.version
v"1.11.8"

julia> result.whenrun
2024-01-01T00:00:00.000

julia> result.runtime
0.123

julia> result.status
:saved
```
"""
function cached(@nospecialize(f), path::AbstractString; overwrite = false)
    # Check file extension
    ext = splitext(path)[2]
    (ext == ".bson" || ext == ".jld2") ||
        throw(ArgumentError("Only `.bson` and `.jld2` files are supported."))

    # Save, overwrite or load
    if !ispath(path) || overwrite
        # Collect metadata and run function
        version = VERSION
        whenrun = now(UTC)
        runtime = @elapsed output = f()
        status  = ispath(path) ? :overwrote : :saved

        # Save metadata and output
        mkpath(dirname(path))
        if ext == ".bson"
            data = Dict(
                :version => version,
                :whenrun => string(whenrun),
                :runtime => runtime,
                :output => output,
            )
            BSON.bson(path, data)
        elseif ext == ".jld2"
            data = Dict(
                "version" => version,
                "whenrun" => whenrun,
                "runtime" => runtime,
                "output" => output,
            )
            JLD2.save(path, data)
        end

        return (; value = output, version, whenrun, runtime, status)
    else
        # Load metadata and output
        status = :loaded
        if ext == ".bson"
            data = BSON.load(path)
            version = data[:version]
            whenrun = DateTime(data[:whenrun])
            runtime = data[:runtime]
            output = data[:output]
        elseif ext == ".jld2"
            data = JLD2.load(path)
            version = data["version"]
            whenrun = data["whenrun"]
            runtime = data["runtime"]
            output = data["output"]
        end

        return (; value = output, version, whenrun, runtime, status)
    end
end
function cached(@nospecialize(f), ::Nothing; kwargs...)
    version = VERSION
    whenrun = now(UTC)
    runtime = @elapsed output = f()
    status  = :disabled
    return (; value = output, version, whenrun, runtime, status)
end
