# Function form tests

@testitem "cache save and load" begin
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
    using Dates
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "cachedtest.$ext")

            # 1. Verify saving
            result = cached(path) do
                x = collect(1:3)
                y = 4
                z = "test"
                return (; x = x, y = y, z = z)
            end

            @test result isa NamedTuple
            @test haskey(result, :value)
            @test haskey(result, :version)
            @test haskey(result, :whenrun)
            @test haskey(result, :runtime)
            @test haskey(result, :status)
            @test result.value == (; x = [1, 2, 3], y = 4, z = "test")
            @test result.version isa VersionNumber
            @test result.whenrun isa DateTime
            @test result.runtime isa Real && result.runtime >= 0
            @test result.status === :saved

            # 2. Verify loading
            result = cached(path) do
                x = collect(1:3)
                y = 4
                z = "test"
                return (; x = x, y = y, z = z)
            end

            @test result isa NamedTuple
            @test haskey(result, :value)
            @test haskey(result, :version)
            @test haskey(result, :whenrun)
            @test haskey(result, :runtime)
            @test haskey(result, :status)
            @test result.value == (; x = [1, 2, 3], y = 4, z = "test")
            @test result.version isa VersionNumber
            @test result.whenrun isa DateTime
            @test result.runtime isa Real && result.runtime >= 0
            @test result.status === :loaded
        end
    end
end

@testitem "cached with path == nothing" begin
    using Dates
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
    @test haskey(result, :status)
    @test result.value == (; x = [1, 2, 3], y = 4, z = "test")
    @test result.version isa VersionNumber
    @test result.whenrun isa DateTime
    @test result.runtime isa Real && result.runtime >= 0
    @test result.status === :disabled
end

@testitem "cached with overwrite" begin
    using Dates
    mktempdir(@__DIR__; prefix = "temp_") do dirpath
        @testset "$ext" for ext in ["bson", "jld2"]
            path = joinpath(dirpath, "cachedoverwrite.$ext")

            # 1. Save initial cache
            result1 = cached(path; overwrite=true) do
                return "first value"
            end

            # 2. Sleep to ensure timestamp difference
            sleep(0.1)

            # 3. Overwrite the cache with different value
            result2 = cached(path; overwrite=true) do
                return "second value"
            end

            # 4. Verify statuses, values, and timestamps
            @test result1.status === :saved
            @test result2.status === :overwrote
            @test result2.value == "second value"
            @test result2.whenrun > result1.whenrun  # timestamp should be newer
        end
    end
end
