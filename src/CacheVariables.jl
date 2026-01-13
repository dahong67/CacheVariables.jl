module CacheVariables

using BSON
using FileIO
import Dates
import Logging: @info

export @cache, cache, cachemeta

function _cachevars(ex::Expr)
    (ex.head === :(=)) && return Symbol[ex.args[1]]
    (ex.head === :block) && return collect(Iterators.flatten([
        _cachevars(exi) for exi in ex.args if isa(exi, Expr)
    ]))
    return Vector{Symbol}(undef, 0)
end

"""
    @cache path code [overwrite]

Cache results from running `code` using the file at `path`.
Load if the file exists; run and save if it does not.
Run and save either way if `overwrite` is true (default is false).

The file format is determined by the file extension (e.g., `.bson`, `.jld2`, `.mat`).

Tip: Use `begin...end` for `code` to cache blocks of code.

Caveat: The variable name `ans` is used for storing the final output,
so it is best to avoid using it as a variable name in `code`.

# Examples
```julia-repl
julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end
┌ Info: Saving to test.bson
│ a
└ b
100

julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end
┌ Info: Loading from test.bson
│ a
└ b
100

julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end true
┌ Info: Overwriting test.bson
│ a
└ b
100
```
"""
macro cache(path, ex::Expr, overwrite = false)
    vars = _cachevars(ex)
    vardesc = join(string.(vars), "\n")
    varkws = [:($(var) = $(var)) for var in vars]
    varlist = :($(varkws...),)
    vartuple = :($(vars...),)

    return quote
        if !ispath($(esc(path))) || $(esc(overwrite))
            _ans = $(esc(ex))
            _msg = ispath($(esc(path))) ? "Overwriting " : "Saving to "
            @info(string(_msg, $(esc(path)), "\n", $(vardesc)))
            mkpath(splitdir($(esc(path)))[1])
            _data = Dict{String,Any}()
            $([:(_data[$(String(var))] = $(esc(var))) for var in vars]...)
            _data["ans"] = _ans
            FileIO.save($(esc(path)), _data)
            _ans
        else
            @info(string("Loading from ", $(esc(path)), "\n", $(vardesc)))
            _data = FileIO.load($(esc(path)))
            $(esc(vartuple)) = getindex.(Ref(_data), $(map(String, vars)))
            _data["ans"]
        end
    end
end

"""
    cache(f, path; kwargs...)

Cache output from running `f()` using the file at `path`.
Load if the file exists; run and save if it does not.

The file format is determined by the file extension (e.g., `.bson`, `.jld2`, `.mat`).

Additional keyword arguments are passed to the underlying save/load functions.
For BSON files, you can pass `mod = @__MODULE__` to specify the module for loading.

Tip: Use `do...end` to cache output from a block of code.

# Examples
```julia-repl
julia> cache("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Saving to test.bson
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> cache("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Loading from test.bson
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> cache("test.jld2") do
         return Dict("result" => 42)
       end
[ Info: Saving to test.jld2
Dict{String, Int64} with 1 entry:
  "result" => 42
```
"""
function cache(@nospecialize(f), path; kwargs...)
    if !ispath(path)
        ans = f()
        @info(string("Saving to ", path, "\n"))
        mkpath(splitdir(path)[1])
        # For BSON files, use BSON.jl directly to maintain compatibility
        if endswith(path, ".bson")
            bson(path; ans = ans)
        else
            FileIO.save(path, Dict("ans" => ans); kwargs...)
        end
        return ans
    else
        @info(string("Loading from ", path, "\n"))
        # For BSON files with mod argument, use BSON.load directly
        if endswith(path, ".bson") && haskey(kwargs, :mod)
            data = BSON.load(path, kwargs[:mod])
            return data[:ans]
        else
            data = FileIO.load(path; kwargs...)
            # BSON through FileIO returns Symbol keys, others return String keys
            return get(data, "ans", get(data, :ans, nothing))
        end
    end
end
function cache(@nospecialize(f), ::Nothing; kwargs...)
    @info("No path provided, running without caching.")
    return f()
end

"""
    cachemeta(f, path; kwargs...)

Cache output from running `f()` using the file at `path` with additional metadata.
Load if the file exists; run and save if it does not.

The file format is determined by the file extension (e.g., `.bson`, `.jld2`, `.mat`).

Additional keyword arguments are passed to the underlying save/load functions.
For BSON files, you can pass `mod = @__MODULE__` to specify the module for loading.

Saves and displays the following metadata:
- Julia version (from `VERSION`)
- Time when run (from `Dates.now(Dates.UTC)`)
- Runtime of code (in seconds)

Tip: Use `do...end` to cache output from a block of code.

# Examples
```julia-repl
julia> cachemeta("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Saving to test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> cachemeta("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Loading from test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```
"""
function cachemeta(@nospecialize(f), path; kwargs...)
    version, whenrun, runtime, ans = cache(path; kwargs...) do
        version = VERSION
        whenrun = Dates.now(Dates.UTC)
        runtime = @elapsed ans = f()
        return (version, whenrun, runtime, ans)
    end
    @info "Run was started at $whenrun and took $runtime seconds."
    return ans
end

end # module
