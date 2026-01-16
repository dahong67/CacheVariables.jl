@testitem "@cache save" begin
    using CacheVariables, BSON, Dates

    ## Add data directory, define data file path
    dirpath = joinpath(@__DIR__, "..", "data")
    mkpath(dirpath)
    path = joinpath(dirpath, "test.bson")

    # 1. Verify log messages for saving
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, r"^Saved cached values to .+\.")
    @test_logs log1 log2 (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end)

    # 2. Delete cache and run again
    rm(path)
    out = @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 3. Verify that the variables enter the workspace correctly
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"

    # Clean up
    rm(path; force = true)
end

@testitem "@cache load" begin
    using CacheVariables, BSON, Dates

    ## Add data directory, define data file path
    dirpath = joinpath(@__DIR__, "..", "data")
    mkpath(dirpath)
    path = joinpath(dirpath, "test-load.bson")

    # First, create the cache file
    @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 1. Reset the variables
    x = y = z = out = nothing

    # 2. Verify log messages for loading
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, r"^Loaded cached values from .+\.")
    @test_logs log1 log2 (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end)

    # 3. Load variables
    out = @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 4. Verify that the variables enter the workspace correctly
    @test x == [1, 2, 3]
    @test y == 4
    @test z == "test"
    @test out == "final output"

    # Clean up
    rm(path; force = true)
end

@testitem "@cache overwrite = value" begin
    using CacheVariables, BSON, Dates

    ## Add data directory, define data file path
    dirpath = joinpath(@__DIR__, "..", "data")
    mkpath(dirpath)
    path = joinpath(dirpath, "test-overwrite-value.bson")

    # Create initial cache
    @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 1. Change file contents
    bson(
        path;
        version = VERSION,
        whenrun = Dates.now(Dates.UTC),
        runtime = 0.0,
        val = (vars = (x = nothing, y = nothing, z = nothing), ans = nothing),
    )

    # 2. Verify log messages for overwriting
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, r"^Overwrote .+ with cached values\.")
    @test_logs log1 log2 (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end overwrite = true)

    # 3. Verify that correct data was written
    x = y = z = out = nothing
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

    # Clean up
    rm(path; force = true)
end

@testitem "@cache overwrite" begin
    using CacheVariables, BSON, Dates

    ## Add data directory, define data file path
    dirpath = joinpath(@__DIR__, "..", "data")
    mkpath(dirpath)
    path = joinpath(dirpath, "test-overwrite.bson")

    # Create initial cache
    @cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end

    # 1. Change file contents
    bson(
        path;
        version = VERSION,
        whenrun = Dates.now(Dates.UTC),
        runtime = 0.0,
        val = (vars = (x = nothing, y = nothing, z = nothing), ans = nothing),
    )

    # 2. Verify log messages for overwriting
    log1 = (:info, "Variable assignments found: x, y, z")
    log2 = (:info, r"^Overwrote .+ with cached values\.")
    overwrite = true
    @test_logs log1 log2 (@cache path begin
        x = collect(1:3)
        y = 4
        z = "test"
        "final output"
    end overwrite)

    # 3. Verify that correct data was written
    x = y = z = out = nothing
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

    # Clean up
    rm(path; force = true)
end

@testitem "@cache no assigned variables" begin
    using CacheVariables, BSON, Dates

    ## Add data directory, define data file path
    dirpath = joinpath(@__DIR__, "..", "data")
    mkpath(dirpath)
    path = joinpath(dirpath, "test-no-vars.bson")

    # 1. Verify log messages for saving
    log1 = (:info, "No variable assignments found")
    log2 = (:info, r"^Saved cached values to .+\.")
    @test_logs log1 log2 (@cache path begin
        2 + 3
    end)

    # 2. Delete cache and run again
    rm(path)
    out = @cache path begin
        2 + 3
    end

    # 3. Verify the output
    @test out == 5

    # 4. Reset the output variable
    out = nothing

    # 5. Verify log messages for loading
    log1 = (:info, "No variable assignments found")
    log2 = (:info, r"^Loaded cached values from .+\.")
    @test_logs log1 log2 (@cache path begin
        2 + 3
    end)

    # 6. Load variables
    out = @cache path begin
        2 + 3
    end

    # 7. Verify the output
    @test out == 5

    # Clean up
    rm(path; force = true)
end

@testitem "@cache complicated begin...end block" begin
    using CacheVariables, BSON, Dates

    ## Add data directory, define data file path
    dirpath = joinpath(@__DIR__, "..", "data")
    mkpath(dirpath)
    path = joinpath(dirpath, "test-complicated.bson")

    # 1. Save and verify log messages
    log1 = (:info, "Variable assignments found: a1, a2, b1, b2, c, d, e, f, g, h, j")
    log2 = (:info, r"^Saved cached values to .+\.")
    @test_logs log1 log2 (@cache path begin
        (; a1, a2) = (a1 = 1, a2 = 2)  # assignment by named tuple destructuring
        b1, b2 = "test", 2             # assignment by tuple destructuring
        c = begin                      # assignments in begin block
            d = 3                      # new assignment should be included
            e = 4                      # new assignment should be included
            d + e                      # final answer is assigned to c
        end
        begin                          # assignments in begin block
            f = 2                      # new assignment should be included
            g = "test"                 # new assignment should be included
        end
        h = let                        # assignments in let block
            i = 1                      # new assignment should be included
            g = 2                      # overwrites earlier g b/c in-function scoping
        end
        @show j = 10                   # new assignment in macro should be included
    end)

    # 2. Verify that the variables enter the workspace correctly
    @test a1 == 1
    @test a2 == 2
    @test b1 == "test"
    @test b2 == 2
    @test c == 7
    @test d == 3
    @test e == 4
    @test f == 2
    @test g == 2  # overwritten inside the let block b/c in-function scoping
    @test h == 2
    @test !@isdefined(i)
    @test j == 10

    # 3. Reset the variables
    a1 = a2 = b1 = b2 = c = d = e = f = g = h = j = nothing

    # 4. Load and verify log messages
    log1 = (:info, "Variable assignments found: a1, a2, b1, b2, c, d, e, f, g, h, j")
    log2 = (:info, r"^Loaded cached values from .+\.")
    @test_logs log1 log2 (@cache path begin
        (; a1, a2) = (a1 = 1, a2 = 2)  # assignment by named tuple destructuring
        b1, b2 = "test", 2             # assignment by tuple destructuring
        c = begin                      # assignments in begin block
            d = 3                      # new assignment should be included
            e = 4                      # new assignment should be included
            d + e                      # final answer is assigned to c
        end
        begin                          # assignments in begin block
            f = 2                      # new assignment should be included
            g = "test"                 # new assignment should be included
        end
        h = let                        # assignments in let block
            i = 1                      # new assignment should be included
            g = 2                      # overwrites earlier g b/c in-function scoping
        end
        @show j = 10                   # new assignment in macro should be included
    end)

    # 5. Verify that the variables enter the workspace correctly
    @test a1 == 1
    @test a2 == 2
    @test b1 == "test"
    @test b2 == 2
    @test c == 7
    @test d == 3
    @test e == 4
    @test f == 2
    @test g == 2  # overwritten inside the let block b/c in-function scoping
    @test h == 2
    @test !@isdefined(i)
    @test j == 10

    # Clean up
    rm(path; force = true)
end

@testitem "@cache unsupported patterns" begin
    using CacheVariables

    # Not a supported pattern
    @test_throws ArgumentError @macroexpand @cache "test.bson" x + 1

    # Unsupported keyword argument
    @test_throws ArgumentError @macroexpand @cache "test.bson" begin
        x = 1
    end unsupported_kwarg = true
end
