module CacheVariables

using BSON
using JLD2
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

The file format is determined by the file extension: `.bson` or `.jld2`.

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
            # Determine format by extension
            if endswith($(esc(path)), ".bson")
                # Use BSON.bson to maintain backward compatibility (Symbol keys)
                bson($(esc(path)); $(esc(varlist))..., ans = _ans)
            elseif endswith($(esc(path)), ".jld2")
                # Use JLD2 for better type support
                _data = Dict{String,Any}()
                $([:(_data[$(String(var))] = $(esc(var))) for var in vars]...)
                _data["ans"] = _ans
                JLD2.jldsave($(esc(path)); _data...)
            else
                error("Unsupported file extension for $($(esc(path))). Only .bson and .jld2 are supported.")
            end
            _ans
        else
            @info(string("Loading from ", $(esc(path)), "\n", $(vardesc)))
            # Determine format by extension
            if endswith($(esc(path)), ".bson")
                _data = BSON.load($(esc(path)), @__MODULE__)
                # BSON uses Symbol keys
                _vars_syms = $vars
                $(esc(vartuple)) = getindex.(Ref(_data), _vars_syms)
                _data[:ans]
            elseif endswith($(esc(path)), ".jld2")
                _data = JLD2.load($(esc(path)))
                # JLD2 uses String keys
                _vars_strs = $(map(String, vars))
                $(esc(vartuple)) = map(_vars_strs) do str
                    if haskey(_data, str)
                        _data[str]
                    else
                        error("Cache file $($(esc(path))) missing required key: $str")
                    end
                end
                if haskey(_data, "ans")
                    _data["ans"]
                else
                    error("Cache file $($(esc(path))) missing required key: ans")
                end
            else
                error("Unsupported file extension for $($(esc(path))). Only .bson and .jld2 are supported.")
            end
        end
    end
end

"""
    cache(f, path; kwargs...)

Cache output from running `f()` using the file at `path`.
Load if the file exists; run and save if it does not.

The file format is determined by the file extension: `.bson` or `.jld2`.

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
         return big"123456789012345678901234567890"
       end
[ Info: Saving to test.jld2
123456789012345678901234567890
```
"""
function cache(@nospecialize(f), path; kwargs...)
    if !ispath(path)
        ans = f()
        @info(string("Saving to ", path, "\n"))
        mkpath(splitdir(path)[1])
        # Determine format by extension
        if endswith(path, ".bson")
            # Use BSON.jl directly to maintain compatibility
            bson(path; ans = ans)
        elseif endswith(path, ".jld2")
            # Use JLD2 for better type support
            JLD2.jldsave(path; ans = ans)
        else
            error("Unsupported file extension for $path. Only .bson and .jld2 are supported.")
        end
        return ans
    else
        @info(string("Loading from ", path, "\n"))
        # Determine format by extension
        if endswith(path, ".bson")
            # For BSON files with mod argument, use BSON.load directly
            if haskey(kwargs, :mod)
                data = BSON.load(path, kwargs[:mod])
            else
                data = BSON.load(path)
            end
            return data[:ans]
        elseif endswith(path, ".jld2")
            # Use JLD2
            data = JLD2.load(path)
            if haskey(data, "ans")
                return data["ans"]
            else
                error("Cache file $path does not contain required 'ans' key. File may be corrupted or incompatible.")
            end
        else
            error("Unsupported file extension for $path. Only .bson and .jld2 are supported.")
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

The file format is determined by the file extension: `.bson` or `.jld2`.

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
