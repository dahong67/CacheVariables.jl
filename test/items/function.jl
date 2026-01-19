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
