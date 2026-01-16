@testitem "cache save and load" begin
    using CacheVariables, BSON, Dates

    ## Add data directory, define data file path
    dirpath = joinpath(@__DIR__, "..", "data")
    mkpath(dirpath)
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

    # 6. Load output
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

    # Clean up
    rm(funcpath; force = true)
end

@testitem "cache with path == nothing" begin
    using CacheVariables

    out = @test_logs cache(nothing) do
        x = collect(1:3)
        y = 4
        z = "test"
        return (; x = x, y = y, z = z)
    end
    @test out == (; x = [1, 2, 3], y = 4, z = "test")
end
