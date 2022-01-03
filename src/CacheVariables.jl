module CacheVariables

using BSON
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
    @cache path code [overwrite]

Cache results from running `code` using BSON file at `path`.
Load if the file exists; run and save if it does not.
Run and save either way if `overwrite` is true (default is false).

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
            bson($(esc(path)); $(esc(varlist))..., ans = _ans)
            _ans
        else
            @info(string("Loading from ", $(esc(path)), "\n", $(vardesc)))
            data = BSON.load($(esc(path)), @__MODULE__)
            $(esc(vartuple)) = getindex.(Ref(data), $vars)
            data[:ans]
        end
    end
end

"""
    cache(f, path)

Cache output from running `f()` using BSON file at `path`.
Load if the file exists; run and save if it does not.

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
```
"""
function cache(@nospecialize(f), path)
    if !ispath(path)
        ans = f()
        @info(string("Saving to ", path, "\n"))
        mkpath(splitdir(path)[1])
        bson(path; ans = ans)
        return ans
    else
        @info(string("Loading from ", path, "\n"))
        data = BSON.load(path, @__MODULE__)
        return data[:ans]
    end
end

end # module
