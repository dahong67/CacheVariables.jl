# CacheVariables.jl

[![version](https://juliahub.com/docs/General/CacheVariables/stable/version.svg)](https://juliahub.com/ui/Packages/General/CacheVariables)
[![Project Status: Active – The project has reached a stable, usable state and is being actively developed.](https://www.repostatus.org/badges/latest/active.svg)](https://www.repostatus.org/#active)
[![CI](https://github.com/dahong67/CacheVariables.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/dahong67/CacheVariables.jl/actions/workflows/CI.yml)
[![Coverage](https://codecov.io/gh/dahong67/CacheVariables.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/dahong67/CacheVariables.jl)

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
```

If the path is set to `nothing`, then caching is skipped and the function is simply run.
```julia
julia> cache(nothing) do
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           return (; a = a, b = b)
       end
(a = "a very time-consuming quantity to compute", b = "a very long simulation to run")
```
This can be useful for conditionally saving a cache (see [Using pattern 3 on a cluster](#using-pattern-3-on-a-cluster) below).

## Macro form

The macro form automatically caches the variables defined in a `begin...end` block.

```julia
@cache "test.bson" begin
    a = "a very time-consuming quantity to compute"
    b = "a very long simulation to run"
    100
end
```

The first time this block runs,
it identifies the variables `a` and `b` and saves them
along with the final output `100`.
Subsequent runs load the saved values from the file `test.bson`
rather than re-running the potentially time-consuming computations!

An example of the output:

```julia
julia> using CacheVariables

julia> @cache "test.bson" begin
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           100
       end
[ Info: Variable assignments found: a, b
┌ Info: Saved cached values to test.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
100

julia> @cache "test.bson" begin
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           100
       end
[ Info: Variable assignments found: a, b
┌ Info: Loaded cached values from test.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
100
```

An optional `overwrite` keyword argument (default is false)
tells the macro to always save,
even when a file with the given name already exists.

```julia
julia> @cache "test.bson" begin
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           100
       end
[ Info: Variable assignments found: a, b
┌ Info: Loaded cached values from test.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
100

julia> @cache "test.bson" begin
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           100
       end overwrite=true
[ Info: Variable assignments found: a, b
┌ Info: Overwrote test.bson with cached values.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
100
```

Internally, this simply wraps the provided code into a function and calls `cache`,
so the relevant scoping rules apply.
This can produce potentially suprising behavior,
as shown by the following example:

```julia
julia> @cache "test-with-let.bson" begin
           a = "a very time-consuming quantity to compute"
           b = "a very long simulation to run"
           let
               c = "this will not be cached"
               b = "this will overwrite the variable b"
           end
           let
               local b = "this will not overwrite b"
           end
           100
       end
[ Info: Variable assignments found: a, b
┌ Info: Saved cached values to test-with-let.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
100

julia> a, b    # b was overwritten in the first let block but not the second
("a very time-consuming quantity to compute", "this will overwrite the variable b")
```

> [!WARNING]
> This macro works by parsing the block to identify which variables have been assigned in it.
> This should generally work, but may not always catch all the variables - check the list
> printed out to make sure. The function form `cache` can be used for more control.

## File formats

CacheVariables.jl supports two file formats, determined by the file extension:

- `.bson`: save using [BSON.jl](https://github.com/JuliaIO/BSON.jl),
  which is a lightweight format that works well for many Julia objects.
- `.jld2`: save using [JLD2.jl](https://github.com/JuliaIO/JLD2.jl),
  which may provide better support for arbitrary Julia types.

Simply change the file extension to switch between formats:

```julia
# Using BSON format
cache("results.bson") do
    # cached computations
end

# Using JLD2 format
cache("results.jld2") do
    # cached computations
end
```

The same works for the macro form:

```julia
# Using BSON format
@cache "results.bson" begin
    # cached computations
end

# Using JLD2 format
@cache "results.jld2" begin
    # cached computations
end
```

The module context for loading BSON files can be set via the `bson_mod` keyword argument:

```julia
cache("data.bson"; bson_mod = @__MODULE__) do
    # cached computations
end
```

This may be useful when working in modules or in Pluto notebooks
(see the [BSON.jl documentation](https://github.com/JuliaIO/BSON.jl?tab=readme-ov-file#loading-custom-data-types-within-modules)
for more detail).

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
┌ Info: Saved cached values to test.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
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
┌ Info: Loaded cached values from test.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
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
┌ Info: Saved cached values to cache/run-1.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
┌ Info: Saved cached values to cache/run-2.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
┌ Info: Saved cached values to cache/run-3.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
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
┌ Info: Loaded cached values from cache/run-1.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
┌ Info: Loaded cached values from cache/run-2.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
┌ Info: Loaded cached values from cache/run-3.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
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
┌ Info: Saved cached values to cache/run-2.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
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
┌ Info: Saved cached values to cache/run-1.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
┌ Info: Saved cached values to cache/run-2.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
┌ Info: Saved cached values to cache/run-3.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
┌ Info: Saved cached values to fullsweep.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
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
┌ Info: Loaded cached values from fullsweep.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
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
┌ Info: Saved cached values to cache/run-2.bson.
│   Run Timestamp : 2024-01-01T00:00:00.000 UTC (run took 0.123 sec)
└   Julia Version : 1.11.8
1-element Vector{String}:
 "time-consuming result of run 2"
```
Note that the full cache was not generated here.

## Example: Caching large Makie figures in Pluto notebooks

Plotting a large amount of data can be quite time-consuming!
The following code shows how a Makie figure can be easily cached
in the context of a Pluto notebook
(similar approaches should be possible in other contexts):

```julia
using CacheVariables, CairoMakie
cache("fig.bson") do
    fig = Figure()
    ax = Axis(fig[1,1])
    for f in 1:1000
        lines!(ax, sin.(f.*(0:0.02pi:2pi)))
    end
    HTML(repr("text/html", fig))
end
```

The first time this code is run, it generates the figure
(in HTML form since we are in a Pluto notebook)
and saves the result.

The next time this code is run, it simply
loads and displays the saved HTML representation,
which can be much faster!

## Related packages

- [Memoization.jl](https://github.com/marius311/Memoization.jl)
