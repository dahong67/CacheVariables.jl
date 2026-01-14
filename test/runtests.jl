using CacheVariables, BSON, Dates, JLD2, Test

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

    # 4. Nothing case
    @test_logs (:info, "No path provided, running without caching.") cache(nothing) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end
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

## Test cachemeta function form
@testset "cachemeta form" begin
    metapath = joinpath(dirpath, "metatest.bson")

    # 1a. Save - verify log messages (at least check for "Saving to" message)
    @test_logs (:info, "Saving to $metapath\n") match_mode=:any cachemeta(metapath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 1b. Save - save values to cache
    rm(metapath)
    out = cachemeta(metapath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 1c. Save - did output return correctly?
    @test out == (; x = [1, 2, 3], y = 4, z = "test")

    # 1d. Verify metadata was saved (stored as tuple with VERSION, timestamp, runtime, result)
    data = BSON.load(metapath)
    @test haskey(data, :ans)
    result_tuple = data[:ans]
    @test result_tuple isa Tuple
    @test length(result_tuple) == 4
    @test result_tuple[1] isa VersionNumber  # VERSION
    @test result_tuple[2] isa Dates.DateTime  # timestamp
    @test result_tuple[3] isa Real  # runtime
    @test result_tuple[3] >= 0
    @test result_tuple[4] == (; x = [1, 2, 3], y = 4, z = "test")  # actual result

    # 2. Reset - set all variables to nothing
    out = nothing

    # 3a. Load - verify log message (at least check for "Loading from" message)
    @test_logs (:info, "Loading from $metapath\n") match_mode=:any cachemeta(metapath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 3b. Load - load values from cache
    out = cachemeta(metapath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 3c. Load - did output return correctly?
    @test out == (; x = [1, 2, 3], y = 4, z = "test")
end

module MyMetaModule
using CacheVariables, Test, DataFrames

@testset "cachemeta form - in module" begin
    # 0. module test path
    dirpath = joinpath(@__DIR__, "data")
    modpath = joinpath(dirpath, "metamodtest.bson")

    # 1a. save
    out = cachemeta(modpath; mod = @__MODULE__) do
        DataFrame(a = 1:10, b = 'a':'j')
    end

    # 1b. check: did variables enter workspace correctly?
    @test out == DataFrame(a = 1:10, b = 'a':'j')

    # 2. set all variables to nothing
    out = nothing

    # 3a. load
    out = cachemeta(modpath; mod = @__MODULE__) do
        DataFrame(a = 1:10, b = 'a':'j')
    end

    # 3b. check: did variables enter workspace correctly?
    @test out == DataFrame(a = 1:10, b = 'a':'j')
end

end

## Test JLD2 format - function form
@testset "JLD2 format - function form" begin
    jld2path = joinpath(dirpath, "jld2test.jld2")

    # 1a. Save - verify log message
    @test_logs (:info, "Saving to $jld2path\n") cache(jld2path) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 1b. Save - save values to cache
    rm(jld2path)
    out = cache(jld2path) do
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
    @test_logs (:info, "Loading from $jld2path\n") cache(jld2path) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 3b. Load - load values from cache
    out = cache(jld2path) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 3c. Load - did variables enter workspace correctly?
    @test out == (; x = [1, 2, 3], y = 4, z = "test")
end

## Test JLD2 format - macro form
@testset "JLD2 format - macro form" begin
    jld2macropath = joinpath(dirpath, "jld2macro.jld2")

    # 1a. Save - verify log message
    @test_logs (:info, "Saving to $jld2macropath\nx\ny\nz") (@cache jld2macropath begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end)

    # 1b. Save - save values to cache
    isfile(jld2macropath) && rm(jld2macropath)
    out = @cache jld2macropath begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 1c. Save - did variables enter workspace correctly?
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"

    # 2. Reset - set all variables to nothing
    x = nothing
    y = nothing
    z = nothing
    out = nothing

    # 3a. Load - verify log message
    @test_logs (:info, "Loading from $jld2macropath\nx\ny\nz") (@cache jld2macropath begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end)

    # 3b. Load - load values from cache
    out = @cache jld2macropath begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 3c. Load - did variables enter workspace correctly?
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"
end

module MyJLD2Module
using CacheVariables, Test, DataFrames

@testset "JLD2 - in module" begin
    # 0. module test path
    dirpath = joinpath(@__DIR__, "data")
    modpath = joinpath(dirpath, "jld2modtest.jld2")

    # 1a. save
    out = cache(modpath) do
        DataFrame(a = 1:10, b = 'a':'j')
    end

    # 1b. check: did variables enter workspace correctly?
    @test out == DataFrame(a = 1:10, b = 'a':'j')

    # 2. set all variables to nothing
    out = nothing

    # 3a. load
    out = cache(modpath) do
        DataFrame(a = 1:10, b = 'a':'j')
    end

    # 3b. check: did variables enter workspace correctly?
    @test out == DataFrame(a = 1:10, b = 'a':'j')
end

end

## Test error handling for unsupported file extensions
@testset "Unsupported extensions" begin
    # Test with function form
    badpath = joinpath(dirpath, "test.txt")
    @test_throws ErrorException("Unsupported file extension for $badpath. Only .bson and .jld2 are supported.") cache(badpath) do
        42
    end

    # Test with macro form
    badpath2 = joinpath(dirpath, "test.mat")
    @test_throws ErrorException("Unsupported file extension for $badpath2. Only .bson and .jld2 are supported.") @cache badpath2 begin
        x = 1
        x
    end
end

## Test error handling for corrupted JLD2 files
@testset "JLD2 error handling" begin
    corruptpath = joinpath(dirpath, "corrupt.jld2")
    
    # Create a JLD2 file without the required "ans" key
    JLD2.jldsave(corruptpath; other_key = 42)
    
    # Test that loading fails with proper error
    @test_throws ErrorException cache(corruptpath) do
        "this should not run"
    end
    
    # Test macro form with missing key
    corruptpath2 = joinpath(dirpath, "corrupt2.jld2")
    JLD2.jldsave(corruptpath2; ans = "test", y = 2)  # missing x key
    
    @test_throws ErrorException @cache corruptpath2 begin
        x = 1
        y = 2
        "result"
    end
end

## Test cachemeta with JLD2
@testset "cachemeta with JLD2" begin
    jld2metapath = joinpath(dirpath, "jld2meta.jld2")

    # 1a. Save - verify log messages
    @test_logs (:info, "Saving to $jld2metapath\n") match_mode=:any cachemeta(jld2metapath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 1b. Save - save values to cache
    isfile(jld2metapath) && rm(jld2metapath)
    out = cachemeta(jld2metapath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 1c. Save - did output return correctly?
    @test out == (; x = [1, 2, 3], y = 4, z = "test")

    # 1d. Verify metadata was saved
    data = JLD2.load(jld2metapath)
    @test haskey(data, "ans")
    result_tuple = data["ans"]
    @test result_tuple isa Tuple
    @test length(result_tuple) == 4
    @test result_tuple[1] isa VersionNumber  # VERSION
    @test result_tuple[2] isa Dates.DateTime  # timestamp
    @test result_tuple[3] isa Real  # runtime
    @test result_tuple[3] >= 0
    @test result_tuple[4] == (; x = [1, 2, 3], y = 4, z = "test")  # actual result

    # 2. Reset
    out = nothing

    # 3a. Load - verify log messages
    @test_logs (:info, "Loading from $jld2metapath\n") match_mode=:any cachemeta(jld2metapath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 3b. Load - load values from cache
    out = cachemeta(jld2metapath) do
        x = collect(1:3)
        y = 4
        z = "test"
        (; x = x, y = y, z = z)
    end

    # 3c. Load - did output return correctly?
    @test out == (; x = [1, 2, 3], y = 4, z = "test")
end

## Clean up
rm(dirpath; recursive = true)
