using CacheVariables, BSON, Dates, Test

## Add data directory, define data file path
dirpath = joinpath(@__DIR__, "data")
isdir(dirpath) && error("Test directory already has a data subdirectory.")
path = joinpath(dirpath, "test.bson")

## Test save behavior of @cache macro
@testset "@cache save" begin
    # 1. Verify log messages for saving
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, r"^Saved cached values to .+\.")
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
    log2 = (:info, r"^Loaded cached values from .+\.")
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

## Test overwrite behavior of @cache macro with `keyword = value` form
@testset "@cache overwrite = value" begin
    # 1. Change file contents
    bson(path; version=VERSION, whenrun=Dates.now(Dates.UTC), runtime=0.0,
        val=(vars=(x=nothing, y=nothing, z=nothing), ans=nothing))

    # 2. Verify log messages for overwriting
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, r"^Overwrote .+ with cached values\.")
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

## Test overwrite behavior of @cache macro with `keyword` form
@testset "@cache overwrite" begin
    # 1. Change file contents
    bson(path; version=VERSION, whenrun=Dates.now(Dates.UTC), runtime=0.0,
        val=(vars=(x=nothing, y=nothing, z=nothing), ans=nothing))

    # 2. Verify log messages for overwriting
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, r"^Overwrote .+ with cached values\.")
    overwrite = true
    @test_logs log1 log2 (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end overwrite)

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
    log2 = (:info, r"^Saved cached values to .+\.")
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
    log2 = (:info, r"^Loaded cached values from .+\.")
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
    log2 = (:info, r"^Saved cached values to .+\.")
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
    log2 = (:info, r"^Loaded cached values from .+\.")
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

## Test unsupported patterns for @cache
@testset "@cache unsupported patterns" begin
    # Not a supported pattern
    @test_throws ArgumentError @macroexpand @cache "test.bson" x + 1

    # Unsupported keyword argument
    @test_throws ArgumentError @macroexpand @cache "test.bson" begin
        x = 1
    end unsupported_kwarg = true
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

## Test save and load behavior of cache function
@testset "cache save and load" begin
    funcpath = joinpath(dirpath, "functest.bson")

    # 1. Verify log messages for saving
    log = (:info, r"^Saved cached values to .+\.")
    @test_logs log cache(funcpath) do
        x = collect(1:3)
        y = 4
        z = "test"
        return (; x=x, y=y, z=z)
    end

    # 2. Delete cache and run again
    rm(funcpath)
    out = cache(funcpath) do
        x = collect(1:3)
        y = 4
        z = "test"
        return (; x=x, y=y, z=z)
    end

    # 3. Verify the output
    @test out == (; x=[1, 2, 3], y=4, z="test")

    # 4. Reset the output
    out = nothing

    # 5. Verify log messages for loading
    log = (:info, r"^Loaded cached values from .+\.")
    @test_logs log cache(funcpath) do
        x = collect(1:3)
        y = 4
        z = "test"
        return (; x=x, y=y, z=z)
    end

    # 6. Load output
    out = cache(funcpath) do
        x = collect(1:3)
        y = 4
        z = "test"
        return (; x=x, y=y, z=z)
    end

    # 7. Verify the output
    @test out == (; x=[1, 2, 3], y=4, z="test")

    # 8. Verify the metadata
    data = BSON.load(funcpath)
    @test data[:version] isa VersionNumber
    @test data[:whenrun] isa Dates.DateTime
    @test data[:runtime] isa Real && data[:runtime] >= 0
end

## Test cache function with path == nothing
@testset "cache with path == nothing" begin
    out = @test_logs cache(nothing) do
        x = collect(1:3)
        y = 4
        z = "test"
        return (; x=x, y=y, z=z)
    end
    @test out == (; x=[1, 2, 3], y=4, z="test")
end

## Test cache in a module
module MyCacheModule
using CacheVariables, Test, DataFrames

@testset "cache in a module" begin
    # 0. Define module test path
    dirpath = joinpath(@__DIR__, "data")
    modpath = joinpath(dirpath, "funcmodtest.bson")

    # 1. Save and check the output
    out = cache(modpath; bson_mod=@__MODULE__) do
        DataFrame(a=1:10, b='a':'j')
    end
    @test out == DataFrame(a=1:10, b='a':'j')

    # 2. Reset the output
    out = nothing

    # 3. Load and check the output
    out = cache(modpath; bson_mod=@__MODULE__) do
        DataFrame(a=1:10, b='a':'j')
    end
    @test out == DataFrame(a=1:10, b='a':'j')
end

end

## Clean up
rm(dirpath; recursive=true)
