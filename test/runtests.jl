using CacheVariables, BSON, Dates, Test

## Add data directory, define data file path
dirpath = joinpath(@__DIR__, "data")
isdir(dirpath) && error("Test directory already has a data subdirectory.")
path = joinpath(dirpath, "test.bson")

## Test @cache macro with save functionality
@testset "@cache Save" begin
    # 1. verify log messages (Saving and metadata)
    @test_logs (:info, r"Saving cached values") match_mode=:any (@cache path begin
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

    # 2. did variables enter workspace correctly?
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"
end

## Test @cache macro with load functionality
@testset "@cache Load" begin
    # 1. set all variables to nothing
    x = nothing
    y = nothing
    z = nothing
    out = nothing

    # 2. file exists: load variables from it
    # verify log message
    @test_logs (:info, r"Loaded cached values") match_mode=:any (@cache path begin
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

## Test @cache macro with overwrite behavior
@testset "@cache Overwrite" begin
    # 1. change file contents to invalid data - simulating corrupted cache
    bson(path; version = VERSION, whenrun = Dates.now(Dates.UTC), runtime = 0.0, 
         val = (vars = (x = nothing, y = nothing, z = nothing), ans = nothing))

    # 2. add `true` to @cache call to overwrite
    # validate log message
    @test_logs (:info, r"Overwriting") match_mode=:any (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end true)

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

## Test @cache macro with no variable case
@testset "@cache Only ans" begin
    # 0. Clean up
    rm(path)

    # 1. verify log message
    @test_logs (:info, r"Saving cached values") match_mode=:any (@cache path begin 2 + 3 end)

    # 2. cache ans
    rm(path)
    out = @cache path begin 2 + 3 end

    # 3. did output come out correctly?
    @test out == 5

    # 4. set variable to nothing
    out = nothing

    # 5. file exists: load from it
    # verify log message
    @test_logs (:info, r"Loaded cached values") match_mode=:any (@cache path begin 2 + 3 end)

    # load ans
    out = @cache path begin 2 + 3 end

    # 6. did output come out correctly?
    @test out == 5
end

## Test @cache in module
# Motivated by Pluto and based on test case from:
# https://github.com/JuliaIO/BSON.jl/issues/25
module MyModule
using CacheVariables, Test, DataFrames

@testset "@cache In module" begin
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

## Test cache function form (formerly cachemeta)
@testset "cache form" begin
    funcpath = joinpath(dirpath, "functest.bson")

    # 1a. Save - verify log message
    @test_logs (:info, r"Saving cached values") match_mode=:any cache(funcpath) do
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
    @test_logs (:info, "No cachefile provided - running without caching.") cache(nothing) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end
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
