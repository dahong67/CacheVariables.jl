using CacheVariables, BSON, Test

## Add data directory, define data file path
dirpath = joinpath(@__DIR__, "data")
!isdir(dirpath) && mkdir(dirpath)
path = joinpath(dirpath, "test.bson")

## Test save functionality
@testset "Save" begin
    # 1. verify log message
    @test_logs (:info, "Saving to /home/jk/.julia/dev/CacheVariables/test/data/test.bson\nx\ny\nz") (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
    end)

    rm(path)
    @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
    end

    # 3. did variables enter workspace correctly?
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
end

## Test load functionality
@testset "Load" begin
    # 1. set all variables to nothing
    x = nothing
    y = nothing
    z = nothing

    # 2. file exists: load variables from it
    # verify log message
    @test_logs (:info, "Loading from /home/jk/.julia/dev/CacheVariables/test/data/test.bson\nx\ny\nz") (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
    end)

    # load variables
        @cache path begin
            x = collect(1:3)
            y = 4
            z = "test"
        end

    # 3. did variables enter workspace correctly?
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
end

## Test overwrite behavior
@testset "Overwrite" begin
    # 1. change file contents
    bson(path; x=nothing, y=nothing, z=nothing)

    # 2. add `true` to @cache call to overwrite
    # validate log message
    @test_logs (:info, "Overwriting /home/jk/.julia/dev/CacheVariables/test/data/test.bson\nx\ny\nz") (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
    end true)

    # overwrite data file
    overwrite = true
    @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
    end overwrite

    # 3. check that correct data was overwritten
    @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
    end

    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
end

## Clean up
rm(dirpath; recursive=true)
