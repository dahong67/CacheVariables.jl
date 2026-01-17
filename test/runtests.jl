using TestItemRunner

## Test save and load behavior of @cache macro with BSON format
@testitem "@cache save and load (BSON)" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        path = joinpath(dirpath, "test.bson")

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

        # 4. Reset the variables
        x = y = z = out = nothing

        # 5. Verify log messages for loading
        log1 = (:info, "Variable assignments found: x, y, z")
        log2 = (:info, r"^Loaded cached values from .+\.")
        @test_logs log1 log2 (@cache path begin
            x = collect(1:3)
            y = 4
            z = "test"
            "final output"
        end)

        # 6. Load variables
        out = @cache path begin
            x = collect(1:3)
            y = 4
            z = "test"
            "final output"
        end

        # 7. Verify that the variables enter the workspace correctly
        @test x == [1, 2, 3]
        @test y == 4
        @test z == "test"
        @test out == "final output"
    end
end

## Test overwrite behavior of @cache macro with `keyword = value` form
@testitem "@cache overwrite = value" begin
    using BSON, Dates
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        path = joinpath(dirpath, "test-overwrite-value.bson")

        # 1. Create file with missing contents
        bson(
            path;
            version = VERSION,
            whenrun = Dates.now(Dates.UTC),
            runtime = 0.0,
            val = (vars = (x = nothing, y = nothing, z = nothing), ans = nothing),
        )

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
end

## Test overwrite behavior of @cache macro with `keyword` form
@testitem "@cache overwrite" begin
    using BSON, Dates
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        path = joinpath(dirpath, "test-overwrite.bson")

        # 1. Create file with missing contents
        bson(
            path;
            version = VERSION,
            whenrun = Dates.now(Dates.UTC),
            runtime = 0.0,
            val = (vars = (x = nothing, y = nothing, z = nothing), ans = nothing),
        )

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
end

## Test behavior of @cache macro with no assigned variables
@testitem "@cache no assigned variables" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        path = joinpath(dirpath, "test-no-vars.bson")

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
end

## Test @cache macro on a complicated begin...end block
@testitem "@cache complicated begin...end block" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        path = joinpath(dirpath, "test-complicated.bson")

        # 1. First run - save
        @cache path begin
            (; a1, a2) = (a1 = 1, a2 = 2)  # assignment by named tuple destructuring
            b1, b2 = "test", 2             # assignment by tuple destructuring
            c = begin                      # assignments in begin block
                d = 3                      # new assignment should be included
                e = 4                      # new assignment should be included
                d + e                      # final answer is assigned to c
            end
            begin                          # assignments in begin block
                f = 2                      # new assignment should be included
                g = "test"                 # new assignment should be included
            end
            h = let                        # assignments in let block
                i = 1                      # new assignment should be included
                g = 2                      # overwrites earlier g b/c in-function scoping
            end
            @show j = 10                   # new assignment in macro should be included
        end

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

        # 4. Second run - load
        @cache path begin
            (; a1, a2) = (a1 = 1, a2 = 2)  # assignment by named tuple destructuring
            b1, b2 = "test", 2             # assignment by tuple destructuring
            c = begin                      # assignments in begin block
                d = 3                      # new assignment should be included
                e = 4                      # new assignment should be included
                d + e                      # final answer is assigned to c
            end
            begin                          # assignments in begin block
                f = 2                      # new assignment should be included
                g = "test"                 # new assignment should be included
            end
            h = let                        # assignments in let block
                i = 1                      # new assignment should be included
                g = 2                      # overwrites earlier g b/c in-function scoping
            end
            @show j = 10                   # new assignment in macro should be included
        end

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
end

## Test unsupported patterns for @cache
@testitem "@cache unsupported patterns" begin
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
@testitem "@cache in a module" begin
    module MyModule
    using CacheVariables, Test, DataFrames

    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        modpath = joinpath(dirpath, "modtest.bson")

        # 1. Save and check that variables entered workspace correctly
        out = @cache modpath begin
            d = DataFrame(; a = 1:10, b = 'a':'j')
            "final output"
        end
        @test d == DataFrame(; a = 1:10, b = 'a':'j')
        @test out == "final output"

        # 2. Reset the variables
        d = out = nothing

        # 3. Load and check that variables entered workspace correctly
        out = @cache modpath begin
            d = DataFrame(; a = 1:10, b = 'a':'j')
            "final output"
        end
        @test d == DataFrame(; a = 1:10, b = 'a':'j')
        @test out == "final output"
    end
    end
end

## Test save and load behavior of cache function with BSON format
@testitem "cache save and load (BSON)" begin
    using BSON, Dates
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        funcpath = joinpath(dirpath, "functest.bson")

        # 1. Verify log messages for saving
        log = (:info, r"^Saved cached values to .+\.")
        @test_logs log cache(funcpath) do
            x = collect(1:3)
            y = 4
            z = "test"
            return (; x = x, y = y, z = z)
        end

        # 2. Delete cache and run again
        rm(funcpath)
        out = cache(funcpath) do
            x = collect(1:3)
            y = 4
            z = "test"
            return (; x = x, y = y, z = z)
        end

        # 3. Verify the output
        @test out == (; x = [1, 2, 3], y = 4, z = "test")

        # 4. Reset the output
        out = nothing

        # 5. Verify log messages for loading
        log = (:info, r"^Loaded cached values from .+\.")
        @test_logs log cache(funcpath) do
            x = collect(1:3)
            y = 4
            z = "test"
            return (; x = x, y = y, z = z)
        end

        # 6. Load the output
        out = cache(funcpath) do
            x = collect(1:3)
            y = 4
            z = "test"
            return (; x = x, y = y, z = z)
        end

        # 7. Verify the output
        @test out == (; x = [1, 2, 3], y = 4, z = "test")

        # 8. Verify the metadata
        data = BSON.load(funcpath)
        @test data[:version] isa VersionNumber
        @test data[:whenrun] isa Dates.DateTime
        @test data[:runtime] isa Real && data[:runtime] >= 0
    end
end

## Test cache function with path == nothing
@testitem "cache with path == nothing" begin
    out = @test_logs cache(nothing) do
        x = collect(1:3)
        y = 4
        z = "test"
        return (; x = x, y = y, z = z)
    end
    @test out == (; x = [1, 2, 3], y = 4, z = "test")
end

## Test cache in a module (BSON)
@testitem "cache in a module (BSON)" begin
    module MyCacheModuleBSON
    using CacheVariables, Test, DataFrames

    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        modpath = joinpath(dirpath, "funcmodtest.bson")

        # 1. Save and check the output
        out = cache(modpath; bson_mod = @__MODULE__) do
            return DataFrame(; a = 1:10, b = 'a':'j')
        end
        @test out == DataFrame(; a = 1:10, b = 'a':'j')

        # 2. Reset the output
        out = nothing

        # 3. Load and check the output
        out = cache(modpath; bson_mod = @__MODULE__) do
            return DataFrame(; a = 1:10, b = 'a':'j')
        end
        @test out == DataFrame(; a = 1:10, b = 'a':'j')
    end
    end
end

## Test save and load behavior of cache function with JLD2 format
@testitem "cache save and load (JLD2)" begin
    using JLD2, Dates
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        funcpath = joinpath(dirpath, "functest.jld2")

        # 1. Verify log messages for saving
        log = (:info, r"^Saved cached values to .+\.")
        @test_logs log cache(funcpath) do
            x = collect(1:3)
            y = 4
            z = "test"
            return (; x = x, y = y, z = z)
        end

        # 2. Delete cache and run again
        rm(funcpath)
        out = cache(funcpath) do
            x = collect(1:3)
            y = 4
            z = "test"
            return (; x = x, y = y, z = z)
        end

        # 3. Verify the output
        @test out == (; x = [1, 2, 3], y = 4, z = "test")

        # 4. Reset the output
        out = nothing

        # 5. Verify log messages for loading
        log = (:info, r"^Loaded cached values from .+\.")
        @test_logs log cache(funcpath) do
            x = collect(1:3)
            y = 4
            z = "test"
            return (; x = x, y = y, z = z)
        end

        # 6. Load the output
        out = cache(funcpath) do
            x = collect(1:3)
            y = 4
            z = "test"
            return (; x = x, y = y, z = z)
        end

        # 7. Verify the output
        @test out == (; x = [1, 2, 3], y = 4, z = "test")

        # 8. Verify the metadata
        data = JLD2.load(funcpath)
        @test data["version"] isa VersionNumber
        @test data["whenrun"] isa Dates.DateTime
        @test data["runtime"] isa Real && data["runtime"] >= 0
    end
end

## Test save and load behavior of @cache macro with JLD2 format
@testitem "@cache save and load (JLD2)" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        path = joinpath(dirpath, "test.jld2")

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

        # 4. Reset the variables
        x = y = z = out = nothing

        # 5. Verify log messages for loading
        log1 = (:info, "Variable assignments found: x, y, z")
        log2 = (:info, r"^Loaded cached values from .+\.")
        @test_logs log1 log2 (@cache path begin
            x = collect(1:3)
            y = 4
            z = "test"
            "final output"
        end)

        # 6. Load variables
        out = @cache path begin
            x = collect(1:3)
            y = 4
            z = "test"
            "final output"
        end

        # 7. Verify that the variables enter the workspace correctly
        @test x == [1, 2, 3]
        @test y == 4
        @test z == "test"
        @test out == "final output"
    end
end

## Test cache in a module (JLD2)
@testitem "cache in a module (JLD2)" begin
    module MyCacheModuleJLD2
    using CacheVariables, Test, DataFrames

    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        modpath = joinpath(dirpath, "funcmodtest.jld2")

        # 1. Save and check the output
        out = cache(modpath) do
            return DataFrame(; a = 1:10, b = 'a':'j')
        end
        @test out == DataFrame(; a = 1:10, b = 'a':'j')

        # 2. Reset the output
        out = nothing

        # 3. Load and check the output
        out = cache(modpath) do
            return DataFrame(; a = 1:10, b = 'a':'j')
        end
        @test out == DataFrame(; a = 1:10, b = 'a':'j')
    end
    end
end

## Test error handling for unsupported file extensions
@testitem "unsupported file extensions" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        badpath = joinpath(dirpath, "test.mat")

        # Test with function form
        @test_throws ArgumentError cache(badpath) do
            return 42
        end

        # Test with macro form
        @test_throws ArgumentError @cache badpath begin
            x = 1
        end
    end
end

@run_package_tests
