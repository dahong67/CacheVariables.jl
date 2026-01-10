# CacheVariables.jl

[![CI](https://github.com/dahong67/CacheVariables.jl/workflows/CI/badge.svg)](https://github.com/dahong67/CacheVariables.jl/actions)
[![codecov](https://codecov.io/gh/dahong67/CacheVariables.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/dahong67/CacheVariables.jl)

A lightweight way to save outputs from (expensive) computations.

## Function form

The function form saves the output of running a function
and can be used with the `do...end` syntax.

```julia
cache("test.bson") do
  a = "a very time-consuming quantity to compute"
  b = "a very long simulation to run"
  return (; a = a, b = b)
end
```

The first time this runs,
it saves the output in a BSON file called `test.bson`.
Subsequent runs load the saved output from the file `test.bson`
rather than re-running the potentially time-consuming computations!
Especially handy for long simulations.

An example of the output:

```julia
julia> using CacheVariables

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

## Macro form

The macro form looks at the code to determine what variables to save.

```julia
@cache "test.bson" begin
  a = "a very time-consuming quantity to compute"
  b = "a very long simulation to run"
  100
end
```

The first time this block runs,
it identifies the variables `a` and `b` and saves them
(in addition to the final output `100` that is saved as `ans`)
in a BSON file called `test.bson`.
Subsequent runs load the saved values from the file `test.bson`
rather than re-running the potentially time-consuming computations!
Especially handy for long simulations.

An example of the output:

```julia
julia> using CacheVariables

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
```

An optional `overwrite` flag (default is false) at the end
tells the macro to always save,
even when a file with the given name already exists.

```julia
julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end false
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

## Cachemap form

The `cachemap` function behaves like `map` but caches the result of the mapping operation.
This is useful when you need to apply an expensive computation to each element of a collection.

```julia
cachemap(x -> x^2, "squares.bson", 1:5)
```

The first time this runs, it applies the function to each element and saves the result.
Subsequent runs load the saved result from the file `squares.bson`.

An example of the output:

```julia
julia> using CacheVariables

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
```

You can also cache intermediate results for each element by setting `cache_intermediates = true`.
This creates separate cache files for each element (e.g., `squares_1.bson`, `squares_2.bson`, etc.):

```julia
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

This is particularly useful when individual computations are expensive and you want to be able to reuse
intermediate results even if the full computation doesn't complete.

See also a similar package: [Memoization.jl](https://github.com/marius311/Memoization.jl)

**Caveat:**
The variable name `ans` is used for storing the final output
(`100` in the above examples),
so it is best to avoid using this as a variable name.
