using TestItemRunner

@testitem "@cache save and load" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "test.$ext")

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
end

@testitem "@cache overwrite = value" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "test-overwrite-value.$ext")

            # 1. Create empty file
            write(path, "")

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
end

@testitem "@cache overwrite" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "test-overwrite.$ext")

            # 1. Create empty file
            write(path, "")

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
end

@testitem "@cache with no assigned variables" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "test-no-vars.$ext")

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
end

@testitem "@cache on a complicated begin...end block" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "test-complicated.$ext")

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
                    g = 2                      # overwrites earlier g b/c function scoping
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
            @test g == 2  # overwritten inside the let block b/c function scoping
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
                    g = 2                      # overwrites earlier g b/c function scoping
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
            @test g == 2  # overwritten inside the let block b/c function scoping
            @test h == 2
            @test !@isdefined(i)
            @test j == 10
        end
    end
end

@testitem "@cache error checking" begin
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "test-unsupported.$ext")

            # Unsupported pattern
            @test_throws ArgumentError @macroexpand @cache path x + 1

            # Unsupported keyword argument
            @test_throws ArgumentError @macroexpand @cache path begin
                x = 1
            end unsupported_kwarg = true
        end
    end
end

# Motivated by Pluto and based on test case from:
# https://github.com/JuliaIO/BSON.jl/issues/25
@testitem "@cache/cache in a module" begin
    module MyModule
    using CacheVariables, Test, DataFrames

    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            modpath = joinpath(dirpath, "modtest.$ext")

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

            # 4. Reset the variables and delete the file
            d = out = nothing
            rm(modpath)

            # 5. Save and check the output
            out = cache(modpath; bson_mod = @__MODULE__) do
                return DataFrame(; a = 1:10, b = 'a':'j')
            end
            @test out == DataFrame(; a = 1:10, b = 'a':'j')

            # 6. Reset the output
            out = nothing

            # 7. Load and check the output
            out = cache(modpath; bson_mod = @__MODULE__) do
                return DataFrame(; a = 1:10, b = 'a':'j')
            end
            @test out == DataFrame(; a = 1:10, b = 'a':'j')
        end
    end
    end
end

@testitem "cache save and load" begin
    using BSON, JLD2, Dates
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "functest.$ext")

            # 1. Verify log messages for saving
            log = (:info, r"^Saved cached values to .+\.")
            @test_logs log cache(path) do
                x = collect(1:3)
                y = 4
                z = "test"
                return (; x = x, y = y, z = z)
            end

            # 2. Delete cache and run again
            rm(path)
            out = cache(path) do
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
            @test_logs log cache(path) do
                x = collect(1:3)
                y = 4
                z = "test"
                return (; x = x, y = y, z = z)
            end

            # 6. Load the output
            out = cache(path) do
                x = collect(1:3)
                y = 4
                z = "test"
                return (; x = x, y = y, z = z)
            end

            # 7. Verify the output
            @test out == (; x = [1, 2, 3], y = 4, z = "test")

            # 8. Verify the metadata
            if ext == "bson"
                data = BSON.load(path)
                version = data[:version]
                whenrun = data[:whenrun]
                runtime = data[:runtime]
            else
                data = JLD2.load(path)
                version = data["version"]
                whenrun = data["whenrun"]
                runtime = data["runtime"]
            end
            @test version isa VersionNumber
            @test whenrun isa Dates.DateTime
            @test runtime isa Real && runtime >= 0
        end
    end
end

@testitem "cache with path == nothing" begin
    out = @test_logs cache(nothing) do
        x = collect(1:3)
        y = 4
        z = "test"
        return (; x = x, y = y, z = z)
    end
    @test out == (; x = [1, 2, 3], y = 4, z = "test")
end

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
