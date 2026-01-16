using CacheVariables, BSON, Dates, Test

## Add data directory, define data file path
dirpath = joinpath(@__DIR__, "data")
isdir(dirpath) && error("Test directory already has a data subdirectory.")
path = joinpath(dirpath, "test.bson")

## Test save behavior of @cache macro
@testset "@cache save" begin
    # 1. Verify log messages for saving
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, Regex("^Saved cached values to $path."))
    @test_logs log1 log2 (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end)

    # 2. Delete cache and run again
    rm(path)
    out = @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 3. Verify that the variables enter the workspace correctly
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"
end

## Test load behavior of @cache macro
@testset "@cache load" begin
    # 1. Reset the variables
    x = y = z = out = nothing

    # 2. Verify log messages for loading
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, Regex("^Loaded cached values from $path."))
    @test_logs log1 log2 (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end)

    # 3. Load variables
    out = @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 4. Verify that the variables enter the workspace correctly
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"
end

## Test overwrite behavior of @cache macro
@testset "@cache overwrite" begin
    # 1. Change file contents
    bson(path; version=VERSION, whenrun=Dates.now(Dates.UTC), runtime=0.0,
        val=(vars=(x=nothing, y=nothing, z=nothing), ans=nothing))

    # 2. Verify log messages for overwriting
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, Regex("^Overwrote $path with cached values."))
    @test_logs log1 log2 (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end overwrite = true)

    # 3. Verify that correct data was written
    x = y = z = out = nothing
    out = @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"
end

## Test behavior of @cache macro with no assigned variables
@testset "@cache no assigned variables" begin
    # 0. Clean up
    rm(path)

    # 1. Verify log messages for saving
    log1 = (:info, "No variable assignments found")
    log2 = (:info, Regex("^Saved cached values to $path."))
    @test_logs log1 log2 (@cache path begin
        2 + 3
    end)

    # 2. Delete cache and run again
    rm(path)
    out = @cache path begin
        2 + 3
    end

    # 3. Verify the output
    @test out == 5

    # 4. Reset the output variable
    out = nothing

    # 5. Verify log messages for loading
    log1 = (:info, "No variable assignments found")
    log2 = (:info, Regex("^Loaded cached values from $path."))
    @test_logs log1 log2 (@cache path begin
        2 + 3
    end)

    # 6. Load variables
    out = @cache path begin
        2 + 3
    end

    # 7. Verify the output
    @test out == 5
end

## Test @cache macro on a complicated begin...end block
@testset "@cache complicated begin...end block" begin
    # 0. Clean up
    rm(path)

    # 1. Save and verify log messages
    log1 = (:info, "Variable assignments found: a1, a2, b1, b2, c, d, e, f, g, h, j")
    log2 = (:info, Regex("^Saved cached values to $path."))
    @test_logs log1 log2 (@cache path begin
        (; a1, a2) = (a1=1, a2=2)  # assignment by named tuple destructuring
        b1, b2 = "test", 2         # assignment by tuple destructuring
        c = begin                  # assignments in begin block
            d = 3                  # new assignment should be included
            e = 4                  # new assignment should be included
            d + e                  # final answer is assigned to c
        end
        begin                      # assignments in begin block
            f = 2                  # new assignment should be included
            g = "test"             # new assignment should be included
        end
        h = let                    # assignments in let block
            i = 1                  # new assignment should be included
            g = 2                  # overwrites earlier g b/c in-function scoping
        end
        @show j = 10               # new assignment in macro should be included
    end)

    # 2. Verify that the variables enter the workspace correctly
    @test a1 == 1
    @test a2 == 2
    @test b1 == "test"
    @test b2 == 2
    @test c == 7
    @test d == 3
    @test e == 4
    @test f == 2
    @test g == 2  # overwritten inside the let block b/c in-function scoping
    @test h == 2
    @test !@isdefined(i)
    @test j == 10

    # 3. Reset the variables
    a1 = a2 = b1 = b2 = c = d = e = f = g = h = j = nothing

    # 4. Load and verify log messages
    log1 = (:info, "Variable assignments found: a1, a2, b1, b2, c, d, e, f, g, h, j")
    log2 = (:info, Regex("^Loaded cached values from $path."))
    @test_logs log1 log2 (@cache path begin
        (; a1, a2) = (a1=1, a2=2)  # assignment by named tuple destructuring
        b1, b2 = "test", 2         # assignment by tuple destructuring
        c = begin                  # assignments in begin block
            d = 3                  # new assignment should be included
            e = 4                  # new assignment should be included
            d + e                  # final answer is assigned to c
        end
        begin                      # assignments in begin block
            f = 2                  # new assignment should be included
            g = "test"             # new assignment should be included
        end
        h = let                    # assignments in let block
            i = 1                  # new assignment should be included
            g = 2                  # overwrites earlier g b/c in-function scoping
        end
        @show j = 10               # new assignment in macro should be included
    end)

    # 5. Verify that the variables enter the workspace correctly
    @test a1 == 1
    @test a2 == 2
    @test b1 == "test"
    @test b2 == 2
    @test c == 7
    @test d == 3
    @test e == 4
    @test f == 2
    @test g == 2  # overwritten inside the let block b/c in-function scoping
    @test h == 2
    @test !@isdefined(i)
    @test j == 10
end

## Test @cache in a module
# Motivated by Pluto and based on test case from:
# https://github.com/JuliaIO/BSON.jl/issues/25
module MyModule
using CacheVariables, Test, DataFrames

@testset "@cache in a module" begin
    # 0. Define module test path
    dirpath = joinpath(@__DIR__, "data")
    modpath = joinpath(dirpath, "modtest.bson")

    # 1. Save and check that variables entered workspace correctly
    out = @cache modpath begin
        d = DataFrame(a=1:10, b='a':'j')
        "final output"
    end
    @test d == DataFrame(a=1:10, b='a':'j')
    @test out == "final output"

    # 2. Reset the variables
    d = out = nothing

    # 3. Load and check that variables entered workspace correctly
    out = @cache modpath begin
        d = DataFrame(a=1:10, b='a':'j')
        "final output"
    end
    @test d == DataFrame(a=1:10, b='a':'j')
    @test out == "final output"
end

end

## Test cache function form (formerly cachemeta)
@testset "cache form" begin
    funcpath = joinpath(dirpath, "functest.bson")

    # 1a. Save - verify log message
    @test_logs (:info, r"Saved cached values") match_mode=:any cache(funcpath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 1b. Save - save values to cache
    rm(funcpath)
    out = cache(funcpath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 1c. Save - did output return correctly?
    @test out == (; x = [1, 2, 3], y = 4, z = "test")

    # 2. Reset - set all variables to nothing
    out = nothing

    # 3a. Load - verify log message
    @test_logs (:info, r"Loaded cached values") match_mode=:any cache(funcpath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 3b. Load - load values from cache
    out = cache(funcpath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 3c. Load - did output return correctly?
    @test out == (; x = [1, 2, 3], y = 4, z = "test")
end

module MyCacheModule
using CacheVariables, Test, DataFrames

@testset "cache form - in module" begin
    # 0. module test path
    dirpath = joinpath(@__DIR__, "data")
    modpath = joinpath(dirpath, "funcmodtest.bson")

    # 1a. save
    out = cache(modpath; bson_mod = @__MODULE__) do
        DataFrame(a = 1:10, b = 'a':'j')
    end

    # 1b. check: did output return correctly?
    @test out == DataFrame(a = 1:10, b = 'a':'j')

    # 2. set all variables to nothing
    out = nothing

    # 3a. load
    out = cache(modpath; bson_mod = @__MODULE__) do
        DataFrame(a = 1:10, b = 'a':'j')
    end

    # 3b. check: did output return correctly?
    @test out == DataFrame(a = 1:10, b = 'a':'j')
end

end

## Test cache function with nothing path
@testset "cache with nothing" begin
    # When path is nothing, cache simply runs the function (no caching-related log messages)
    out = cache(nothing) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end
    @test out == (; x = [1, 2, 3], y = 4, z = "test")
end

## Clean up
rm(dirpath; recursive = true)
