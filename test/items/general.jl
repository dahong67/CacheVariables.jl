# General tests

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
