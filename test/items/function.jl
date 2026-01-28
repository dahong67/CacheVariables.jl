# Function form tests

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
                whenrun = DateTime(data[:whenrun])
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

@testitem "cached save and load" begin
    using CacheVariables, BSON, JLD2, Dates
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "cachedtest.$ext")

            # 1. Save and verify result
            result = cached(path) do
                x = collect(1:3)
                y = 4
                z = "test"
                return (; x = x, y = y, z = z)
            end

            # 2. Verify the result structure and value
            @test result isa NamedTuple
            @test haskey(result, :value)
            @test haskey(result, :version)
            @test haskey(result, :whenrun)
            @test haskey(result, :runtime)
            @test result.value == (; x = [1, 2, 3], y = 4, z = "test")
            @test result.version isa VersionNumber
            @test result.whenrun isa Dates.DateTime
            @test result.runtime isa Real && result.runtime >= 0

            # 3. Load and verify the loaded result
            result = cached(path) do
                x = collect(1:3)
                y = 4
                z = "test"
                return (; x = x, y = y, z = z)
            end

            @test result.value == (; x = [1, 2, 3], y = 4, z = "test")
            @test result.version isa VersionNumber
            @test result.whenrun isa Dates.DateTime
            @test result.runtime isa Real && result.runtime >= 0

            # 4. Verify metadata matches what's in the file
            if ext == "bson"
                data = BSON.load(path)
                @test result.version == data[:version]
                @test string(result.whenrun) == data[:whenrun]
                @test result.runtime == data[:runtime]
            else
                data = JLD2.load(path)
                @test result.version == data["version"]
                @test result.whenrun == data["whenrun"]
                @test result.runtime == data["runtime"]
            end
        end
    end
end

@testitem "cached with path == nothing" begin
    using CacheVariables, Dates
    result = cached(nothing) do
        x = collect(1:3)
        y = 4
        z = "test"
        return (; x = x, y = y, z = z)
    end

    # Verify the result structure and value
    @test result isa NamedTuple
    @test haskey(result, :value)
    @test haskey(result, :version)
    @test haskey(result, :whenrun)
    @test haskey(result, :runtime)
    @test result.value == (; x = [1, 2, 3], y = 4, z = "test")
    @test result.version isa VersionNumber
    @test result.whenrun isa Dates.DateTime
    @test result.runtime isa Real && result.runtime >= 0
end

@testitem "cached with overwrite" begin
    using CacheVariables, BSON, JLD2, Dates
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "cachedoverwrite.$ext")

            # 1. Save initial cache
            result1 = cached(path) do
                return "first value"
            end
            first_whenrun = result1.whenrun

            # 2. Sleep to ensure timestamp difference
            sleep(0.1)

            # 3. Overwrite and verify new value
            result2 = cached(path; overwrite=true) do
                return "second value"
            end

            @test result2.value == "second value"
            @test result2.whenrun > first_whenrun  # timestamp should be newer
        end
    end
end
