using CacheVariables, Test

dirpath = joinpath(@__DIR__, "data")
!isdir(dirpath) && mkdir(path)
path = joinpath(dirpath, "test.bson")

@cache path begin
    x = collect(1:3)
    y = 4
    z = "test"
end

@test x == [1, 2, 3]
@test y == 4
@test z == "test"

# overwrite variables, then load and check values again
x = nothing
y = nothing
z = nothing

@cache path begin
    x = collect(1:3)
    y = 4
    z = "test"
end

@test x == [1, 2, 3]
@test y == 4
@test z == "test"

# clean up
rm(dirpath,recursive=true)

# make sure it's gone
@test !isfile(path)
