# Function form

"""
    cache(f, path; overwrite=false)

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
function cache(@nospecialize(f), path::AbstractString; overwrite = false)
    # Determine whether we're saving or loading
    is_loading = ispath(path) && !overwrite
    
    # Call cached to do the actual work
    result = cached(f, path; overwrite = overwrite)
    
    # Form main message for @info
    main_msg = if is_loading
        "Loaded cached values from $path."
    elseif ispath(path)
        "Overwrote $path with cached values."
    else
        "Saved cached values to $path."
    end
    
    # Emit @info log message
    @info """
    $main_msg
      Run Timestamp : $(result.whenrun) UTC (run took $(result.runtime) sec)
      Julia Version : $(result.version)
    """
    
    return result.value
end
cache(@nospecialize(f), ::Nothing; kwargs...) = f()

"""
    cached(f, path; overwrite=false)

Cache the output of running `f()` in a cache file at `path` and return both
the output and metadata as a `NamedTuple`, analogous to `@timed`.

The returned `NamedTuple` has the following fields:
- `value`: The output of running `f()`.
- `version`: The Julia version used when the code was run.
- `whenrun`: The timestamp when the code was run (in UTC).
- `runtime`: The runtime of the code (in seconds).

This function behaves identically to [`cache`](@ref) but returns the metadata
along with the value. This can be useful for unit testing (to check what's been
saved without reading the cache files) or for accumulating metadata from
multiple cache operations.

The file extension of `path` determines the file format used:
`.bson` for [BSON.jl](https://github.com/JuliaIO/BSON.jl) and
`.jld2` for [JLD2.jl](https://github.com/JuliaIO/JLD2.jl).
The `path` can also be set to `nothing` to disable caching and simply run `f()`.
This can be useful for conditionally caching the results.

If `overwrite` is set to true, existing cache files will be overwritten
with the results (and metadata) from a "fresh" call to `f()`.

See also: [`cache`](@ref)

# Examples
```julia-repl
julia> result = cached("test.bson") do
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           return (; a = a, b = b)
       end
(value = (a = "a very time-consuming quantity to compute", b = "a very long simulation to run"), version = v"1.11.8", whenrun = 2024-01-01T00:00:00.000, runtime = 0.123)

julia> result.value
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> result.version
v"1.11.8"

julia> result.runtime
0.123
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

        return (; value = output, version = version, whenrun = whenrun, runtime = runtime)
    else
        # Load metadata and output
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

        return (; value = output, version = version, whenrun = whenrun, runtime = runtime)
    end
end
cached(@nospecialize(f), ::Nothing; kwargs...) = begin
    runtime = @elapsed output = f()
    return (; value = output, version = VERSION, whenrun = now(UTC), runtime = runtime)
end
