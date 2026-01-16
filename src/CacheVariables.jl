module CacheVariables

using BSON
using Dates: UTC, now
using ExpressionExplorer: compute_symbols_state
using Logging: @info
using MacroTools: @capture

export @cache, cache

include("function.jl")
include("macro.jl")

end
