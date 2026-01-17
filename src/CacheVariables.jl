module CacheVariables

using BSON: BSON
using Dates: UTC, now
using ExpressionExplorer: compute_symbols_state
using JLD2: JLD2
using Logging: @info
using MacroTools: @capture

export @cache, cache

include("function.jl")
include("macro.jl")

end
