# CacheVariables.jl

[![CI](https://github.com/dahong67/CacheVariables.jl/workflows/CI/badge.svg)](https://github.com/dahong67/CacheVariables.jl/actions)
[![codecov](https://codecov.io/gh/dahong67/CacheVariables.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/dahong67/CacheVariables.jl)

A lightweight way to save outputs from (expensive) computations.
Supports BSON and JLD2 file formats.

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
it saves the output in a file called `test.bson`.
The file format is determined by the extension (`.bson` or `.jld2`).
Subsequent runs load the saved output from the file
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

If the path is set to `nothing`, then caching is skipped and the function is simply run.
```julia
julia> cache(nothing) do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: No path provided, running without caching.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```
This can be useful for conditionally saving a cache (see [Using pattern 3 on a cluster](#using-pattern-3-on-a-cluster) below).

## File formats

CacheVariables.jl supports two file formats:

- **`.bson`** - [BSON.jl](https://github.com/JuliaIO/BSON.jl) format (works well for most Julia types)
- **`.jld2`** - [JLD2.jl](https://github.com/JuliaIO/JLD2.jl) format (excellent support for arbitrary Julia types, including `BigInt`)

The format is automatically determined by the file extension.

### Using JLD2

JLD2 provides excellent support for arbitrary Julia types and may handle some edge cases better than BSON:

```julia
julia> cache("results.jld2") do
         big_number = big"123456789012345678901234567890"
         data = (; x = 1:10, y = rand(10), z = "results")
         return (; big_number = big_number, data = data)
       end
[ Info: Saving to results.jld2
(big_number = 123456789012345678901234567890, data = (x = 1:10, y = [0.123, ...], z = "results"))

julia> cache("results.jld2") do
         big_number = big"123456789012345678901234567890"
         data = (; x = 1:10, y = rand(10), z = "results")
         return (; big_number = big_number, data = data)
       end
[ Info: Loading from results.jld2
(big_number = 123456789012345678901234567890, data = (x = 1:10, y = [0.123, ...], z = "results"))
```

### Format-specific options

You can pass keyword arguments to the underlying save/load functions.
For BSON files, you can pass the `mod` keyword to specify the module context for loading:

```julia
cache("data.bson"; mod = @__MODULE__) do
    # your computation
end
```

This is particularly useful when working in modules or in Pluto notebooks.

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
in a file called `test.bson`.
The file format is determined by the extension (`.bson` or `.jld2`).
Subsequent runs load the saved values from the file
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

**Caveat:**
The variable name `ans` is used for storing the final output
(`100` in the above examples),
so it is best to avoid using this as a variable name.

## Caching the results of a sweep

It can be common to need to cache the results of a large sweep (e.g., over parameters or trials of a simulation).

### Pattern 1: cache the full sweep

Caching the full sweep can simply be done as follows:

```julia
julia> using CacheVariables

julia> cache("test.bson") do
           map(1:3) do run
               result = "time-consuming result of run $run"
               return result
           end
       end
[ Info: Saving to test.bson
3-element Vector{String}:
 "time-consuming result of run 1"
 "time-consuming result of run 2"
 "time-consuming result of run 3"

julia> cache("test.bson") do
           map(1:3) do run
               result = "time-consuming result of run $run"
               return result
           end
       end
[ Info: Loading from test.bson
3-element Vector{Any}:
 "time-consuming result of run 1"
 "time-consuming result of run 2"
 "time-consuming result of run 3"
```

### Pattern 2: cache each run in the sweep

If each run in the sweep itself takes a very long time,
it can be better to cache each individual run separately
as follows:

```julia
julia> using CacheVariables

julia> map(1:3) do run
           cache(joinpath("cache", "run-$run.bson")) do
               result = "time-consuming result of run $run"
               return result
           end
       end
[ Info: Saving to cache/run-1.bson
[ Info: Saving to cache/run-2.bson
[ Info: Saving to cache/run-3.bson
3-element Vector{String}:
 "time-consuming result of run 1"
 "time-consuming result of run 2"
 "time-consuming result of run 3"

julia> map(1:3) do run
           cache(joinpath("cache", "run-$run.bson")) do
               result = "time-consuming result of run $run"
               return result
           end
       end
[ Info: Loading from cache/run-1.bson
[ Info: Loading from cache/run-2.bson
[ Info: Loading from cache/run-3.bson
3-element Vector{String}:
 "time-consuming result of run 1"
 "time-consuming result of run 2"
 "time-consuming result of run 3"
```

#### Using pattern 2 on a cluster

A convenient aspect of this pattern is that the runs can then be performed independently,
such as on different nodes of a computing cluster.
For example, the following code allows the runs to be spread across a [SLURM job array](https://slurm.schedmd.com/job_array.html):

```julia
julia> using CacheVariables

julia> ENV["SLURM_ARRAY_TASK_ID"] = 2    # simulate run from SLURM job array
2

julia> SUBSET = haskey(ENV, "SLURM_ARRAY_TASK_ID") ?
               (IDX = parse(Int, ENV["SLURM_ARRAY_TASK_ID"]); IDX:IDX) : Colon()
2:2

julia> map((1:3)[SUBSET]) do run
           cache(joinpath("cache", "run-$run.bson")) do
               result = "time-consuming result of run $run"
               return result
           end
       end
[ Info: Saving to cache/run-2.bson
1-element Vector{String}:
 "time-consuming result of run 2"
```

When run on the cluster, this only runs (and caches) the case indexed the job array index.
Then, when the code is run again (off the cluster), the caches from the full sweep will simply be loaded!

### Pattern 3: cache each run in the sweep then merge

Sometimes it's useful to make a merged cache file (e.g., to reduce the number of cache files to commit in git, etc.).
A convenient pattern here is to use **nested** `cache` calls.

```julia
julia> using CacheVariables

julia> cache("fullsweep.bson") do
           map(1:3) do run
               cache(joinpath("cache", "run-$run.bson")) do
                   result = "time-consuming result of run $run"
                   return result
               end
           end
       end
[ Info: Saving to cache/run-1.bson
[ Info: Saving to cache/run-2.bson
[ Info: Saving to cache/run-3.bson
[ Info: Saving to fullsweep.bson
3-element Vector{String}:
 "time-consuming result of run 1"
 "time-consuming result of run 2"
 "time-consuming result of run 3"

julia> cache("fullsweep.bson") do
           map(1:3) do run
               cache(joinpath("cache", "run-$run.bson")) do
                   result = "time-consuming result of run $run"
                   return result
               end
           end
       end
[ Info: Loading from fullsweep.bson
3-element Vector{Any}:
 "time-consuming result of run 1"
 "time-consuming result of run 2"
 "time-consuming result of run 3"
```

Note that only the `fullsweep.bson` cache file was used when loading.
Once this file is produced, the intermediate files (`cache/run-1.bson`, etc.) are no longer needed.

#### Using pattern 3 on a cluster

To use this pattern on a cluster (as in [Using pattern 2 on a cluster](#using-pattern-2-on-a-cluster)),
we need to make sure the outer cache is not formed until we have all the results.

This can be done as follows:

```julia
julia> using CacheVariables

julia> ENV["SLURM_ARRAY_TASK_ID"] = 2    # simulate run from SLURM job array
2

julia> SUBSET = haskey(ENV, "SLURM_ARRAY_TASK_ID") ?
               (IDX = parse(Int, ENV["SLURM_ARRAY_TASK_ID"]); IDX:IDX) : Colon()
2:2

julia> cache(SUBSET === Colon() ? "fullsweep.bson" : nothing) do
           map((1:3)[SUBSET]) do run
               cache(joinpath("cache", "run-$run.bson")) do
                   result = "time-consuming result of run $run"
                   return result
               end
           end
       end
[ Info: No path provided, running without caching.
[ Info: Saving to cache/run-2.bson
1-element Vector{String}:
 "time-consuming result of run 2"
```
Note that the full cache was not generated here.

## Related packages

- [Memoization.jl](https://github.com/marius311/Memoization.jl)
