module CacheVariables

using BSON
import Logging: @info

export @cache, cache, cachemap

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
    cache(f, path; mod = @__MODULE__)

Cache output from running `f()` using BSON file at `path`.
Load if the file exists; run and save if it does not.
Use `mod` keyword argument to specify module.

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
function cache(@nospecialize(f), path; mod = @__MODULE__)
    if !ispath(path)
        ans = f()
        @info(string("Saving to ", path, "\n"))
        mkpath(splitdir(path)[1])
        bson(path; ans = ans)
        return ans
    else
        @info(string("Loading from ", path, "\n"))
        data = BSON.load(path, mod)
        return data[:ans]
    end
end

"""
    cachemap(f, path, args...; cache_intermediates = false, mod = @__MODULE__)

Cache output from mapping function `f` over `args` using BSON file at `path`.
Load if the file exists; run and save if it does not.
Use `mod` keyword argument to specify module.

When `cache_intermediates` is true, also cache intermediate results for each element
at paths derived from `path` (e.g., `path_1`, `path_2`, etc.).

Behaves like `map(f, args...)` but with caching.

# Examples
```julia-repl
julia> cachemap(x -> x^2, "squares.bson", 1:3)
[ Info: Saving to squares.bson
3-element Vector{Int64}:
 1
 4
 9

julia> cachemap(x -> x^2, "squares.bson", 1:3)
[ Info: Loading from squares.bson
3-element Vector{Int64}:
 1
 4
 9

julia> cachemap(x -> x^2, "squares.bson", 1:3; cache_intermediates = true)
[ Info: Saving to squares_1.bson
[ Info: Saving to squares_2.bson
[ Info: Saving to squares_3.bson
[ Info: Saving to squares.bson
3-element Vector{Int64}:
 1
 4
 9
```
"""
function cachemap(@nospecialize(f), path, args...; cache_intermediates = false, mod = @__MODULE__)
    cache(path; mod = mod) do
        if cache_intermediates
            # Validate arguments
            if isempty(args)
                throw(ArgumentError("cachemap requires at least one argument"))
            end
            
            # Generate path for intermediate caching
            dir, filename = splitdir(path)
            base, ext = splitext(filename)
            
            # Get the length from the first argument and validate all have same length
            n = length(first(args))
            for arg in args
                if length(arg) != n
                    throw(ArgumentError("all arguments to cachemap must have the same length"))
                end
            end
            
            # For each index, cache the intermediate result
            results = Vector{Any}(undef, n)
            for i in 1:n
                # Create intermediate path
                intermediate_path = joinpath(dir, string(base, "_", i, ext))
                
                # Cache the intermediate computation
                results[i] = cache(intermediate_path; mod = mod) do
                    # Get elements at index i from all args
                    elems = map(arg -> arg[i], args)
                    f(elems...)
                end
            end
            return results
        else
            # Just cache the final result
            return map(f, args...)
        end
    end
end

end # module
