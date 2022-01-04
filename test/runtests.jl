using CacheVariables, BSON, Test

## Add data directory, define data file path
dirpath = joinpath(@__DIR__, "data")
isdir(dirpath) && error("Test directory already has a data subdirectory.")
path = joinpath(dirpath, "test.bson")

## Test save functionality
@testset "Save" begin
    # 1. verify log message
    @test_logs (:info, "Saving to $path\nx\ny\nz") (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end)

    rm(path)
    out = @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 3. did variables enter workspace correctly?
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"
end

## Test load functionality
@testset "Load" begin
    # 1. set all variables to nothing
    x = nothing
    y = nothing
    z = nothing
    out = nothing

    # 2. file exists: load variables from it
    # verify log message
    @test_logs (:info, "Loading from $path\nx\ny\nz") (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end)

    # load variables
    out = @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 3. did variables enter workspace correctly?
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"
end

## Test overwrite behavior
@testset "Overwrite" begin
    # 1. change file contents
    bson(path; x = nothing, y = nothing, z = nothing, ans = nothing)

    # 2. add `true` to @cache call to overwrite
    # validate log message
    @test_logs (:info, "Overwriting $path\nx\ny\nz") (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end true)

    # overwrite data file
    overwrite = true
    @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end overwrite

    # 3. check that correct data was overwritten
    x = nothing
    y = nothing
    z = nothing
    out = nothing
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

## Test no variable case (where we just save ans)
@testset "Only ans" begin
    # 0. Clean up
    rm(path)

    # 1. verify log message
    @test_logs (:info, "Saving to $path\n") (@cache path 2 + 3)

    # 2. cache ans
    rm(path)
    out = @cache path 2 + 3

    # 3. did variables enter workspace correctly?
    @test out == 5

    # 4. set variable to nothing
    out = nothing

    # 5. file exists: load variables from it
    # verify log message
    @test_logs (:info, "Loading from $path\n") (@cache path 2 + 3)

    # load variables
    out = @cache path 2 + 3

    # 6. did variables enter workspace correctly?
    @test out == 5
end

## Test functionality in module
# Motivated by Pluto and based on test case from:
# https://github.com/JuliaIO/BSON.jl/issues/25
module MyModule
using CacheVariables, Test, DataFrames

@testset "In module" begin
    # 0. module test path
    dirpath = joinpath(@__DIR__, "data")
    modpath = joinpath(dirpath, "modtest.bson")

    # 1a. save
    out = @cache modpath begin
        d = DataFrame(a = 1:10, b = 'a':'j')
        "final output"
    end

    # 1b. check: did variables enter workspace correctly?
    @test d == DataFrame(a = 1:10, b = 'a':'j')
    @test out == "final output"

    # 2. set all variables to nothing
    d = nothing
    out = nothing

    # 3a. load
    out = @cache modpath begin
        d = DataFrame(a = 1:10, b = 'a':'j')
        "final output"
    end

    # 3b. check: did variables enter workspace correctly?
    @test d == DataFrame(a = 1:10, b = 'a':'j')
    @test out == "final output"
end

end

## Test function form
@testset "Function form" begin
    funcpath = joinpath(dirpath, "functest.bson")

    # 1a. Save - verify log message
    @test_logs (:info, "Saving to $funcpath\n") cache(funcpath) do
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

    # 1c. Save - did variables enter workspace correctly?
    @test out == (; x = [1, 2, 3], y = 4, z = "test")

    # 2. Reset - set all variables to nothing
    out = nothing

    # 3a. Load - verify log message
    @test_logs (:info, "Loading from $funcpath\n") cache(funcpath) do
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

    # 3c. Load - did variables enter workspace correctly?
    @test out == (; x = [1, 2, 3], y = 4, z = "test")
end

module MyFuncModule
using CacheVariables, Test, DataFrames

@testset "Function form - in module" begin
    # 0. module test path
    dirpath = joinpath(@__DIR__, "data")
    modpath = joinpath(dirpath, "funcmodtest.bson")

    # 1a. save
    out = cache(modpath; mod = @__MODULE__) do
        DataFrame(a = 1:10, b = 'a':'j')
    end

    # 1b. check: did variables enter workspace correctly?
    @test out == DataFrame(a = 1:10, b = 'a':'j')

    # 2. set all variables to nothing
    out = nothing

    # 3a. load
    out = cache(modpath; mod = @__MODULE__) do
        DataFrame(a = 1:10, b = 'a':'j')
    end

    # 3b. check: did variables enter workspace correctly?
    @test out == DataFrame(a = 1:10, b = 'a':'j')
end

end

## Clean up
rm(dirpath; recursive = true)
