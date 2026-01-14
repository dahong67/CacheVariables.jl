# CacheVariables.jl

[![CI](https://github.com/dahong67/CacheVariables.jl/workflows/CI/badge.svg)](https://github.com/dahong67/CacheVariables.jl/actions)
[![codecov](https://codecov.io/gh/dahong67/CacheVariables.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/dahong67/CacheVariables.jl)

A lightweight way to save outputs from (expensive) computations.

## Macro form

The macro form provides a convenient way to cache blocks of code
with automatic variable handling.

```julia
@cache "test.bson" begin
  a = "a very time-consuming quantity to compute"
  b = "a very long simulation to run"
  100
end
```

The first time this block runs,
it identifies the variables `a` and `b`, saves them along with the final output `100`,
in a BSON file called `test.bson` using the `cache` function.
Subsequent runs load the saved values from the file `test.bson`
rather than re-running the potentially time-consuming computations!
Especially handy for long simulations.

The `@cache` macro transforms your code to use the `cache` function,
so you get metadata tracking (Julia version, timestamp, runtime) automatically.

An example of the output:

```julia
julia> using CacheVariables

julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end
[ Info: Saving to test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
100

julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end
[ Info: Loading from test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
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
[ Info: Loading from test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
100

julia> @cache "test.bson" begin
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         100
       end true
[ Info: Overwriting test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
100
```

The macro can also handle `map` expressions for caching iterations:

```julia
julia> @cache "results" map(1:3) do i
         # expensive computation for iteration i
         "result $i"
       end
[ Info: Saving to results/1
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to results/2
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to results/3
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
3-element Vector{String}:
 "result 1"
 "result 2"
 "result 3"
```

## Function form

The function form saves the output of running a function
and can be used with the `do...end` syntax.
It includes metadata tracking (Julia version, timestamp, runtime).

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
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> cache("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Loading from test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```

An optional `overwrite` flag (default is false)
tells the function to always save,
even when a file with the given name already exists.

```julia
julia> cache("test.bson"; overwrite = true) do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Overwriting test.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```

### Bare cache (no metadata)

For cases where you don't need metadata tracking, use `barecache`:

```julia
julia> barecache("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Saving to test.bson
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")

julia> barecache("test.bson") do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: Loading from test.bson
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```

If the path is set to `nothing`, then caching is skipped and the function is simply run.
```julia
julia> barecache(nothing) do
         a = "a very time-consuming quantity to compute"
         b = "a very long simulation to run"
         return (; a = a, b = b)
       end
[ Info: No path provided, running without caching.
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```
This can be useful for conditionally saving a cache (see [Using pattern 3 on a cluster](#using-pattern-3-on-a-cluster) below).

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
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
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
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
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
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to cache/run-2.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to cache/run-3.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
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
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Loading from cache/run-2.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Loading from cache/run-3.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
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
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
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
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to cache/run-2.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to cache/run-3.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
[ Info: Saving to fullsweep.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
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
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.123 seconds.
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

This can be done as follows (using `barecache` for the conditional caching):

```julia
julia> using CacheVariables

julia> ENV["SLURM_ARRAY_TASK_ID"] = 2    # simulate run from SLURM job array
2

julia> SUBSET = haskey(ENV, "SLURM_ARRAY_TASK_ID") ?
               (IDX = parse(Int, ENV["SLURM_ARRAY_TASK_ID"]); IDX:IDX) : Colon()
2:2

julia> barecache(SUBSET === Colon() ? "fullsweep.bson" : nothing) do
           map((1:3)[SUBSET]) do run
               cache(joinpath("cache", "run-$run.bson")) do
                   result = "time-consuming result of run $run"
                   return result
               end
           end
       end
[ Info: No path provided, running without caching.
[ Info: Saving to cache/run-2.bson
[ Info: Run was started at 2024-01-01T00:00:00.000 and took 0.001 seconds.
1-element Vector{String}:
 "time-consuming result of run 2"
```
Note that the full cache was not generated here.

## Related packages

- [Memoization.jl](https://github.com/marius311/Memoization.jl)
