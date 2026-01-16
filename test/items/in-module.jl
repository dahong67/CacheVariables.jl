@testitem "@cache in a module" begin
    using CacheVariables, DataFrames

    module MyModule
    using CacheVariables, Test, DataFrames

    function run_tests()
        # 0. Define module test path
        dirpath = joinpath(@__DIR__, "..", "..", "data")
        mkpath(dirpath)
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

        # Clean up
        rm(modpath; force = true)
    end
    end

    MyModule.run_tests()
end

@testitem "cache in a module" begin
    using CacheVariables, DataFrames

    module MyCacheModule
    using CacheVariables, Test, DataFrames

    function run_tests()
        # 0. Define module test path
        dirpath = joinpath(@__DIR__, "..", "..", "data")
        mkpath(dirpath)
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

        # Clean up
        rm(modpath; force = true)
    end
    end

    MyCacheModule.run_tests()
end
