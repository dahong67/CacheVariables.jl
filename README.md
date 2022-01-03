# CacheVariables.jl

[![CI](https://github.com/dahong67/CacheVariables.jl/workflows/CI/badge.svg)](https://github.com/dahong67/CacheVariables.jl/actions)
[![codecov](https://codecov.io/gh/dahong67/CacheVariables.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/dahong67/CacheVariables.jl)

A lightweight way to save outputs from (expensive) computations.

## Function form

The function form saves the output of running a function,
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

See also a similar package: [Memoization.jl](https://github.com/marius311/Memoization.jl)

**Caveat:**
The variable name `ans` is used for storing the final output
(`100` in the above examples),
so it is best to avoid using this as a variable name.
