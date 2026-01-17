# Aqua

@testitem "Method ambiguities" begin
    using Aqua: test_ambiguities
    test_ambiguities(CacheVariables)
end

@testitem "Unbound type parameters" begin
    using Aqua: test_unbound_args
    test_unbound_args(CacheVariables)
end

@testitem "Undefined exports" begin
    using Aqua: test_undefined_exports
    test_undefined_exports(CacheVariables)
end

@testitem "Stale dependencies" begin
    using Aqua: test_stale_deps
    test_stale_deps(CacheVariables)
end

@testitem "Compat entries" begin
    using Aqua: test_deps_compat
    test_deps_compat(CacheVariables)
end

@testitem "Type piracy" begin
    using Aqua: test_piracies
    test_piracies(CacheVariables)
end

@testitem "Persistent tasks" begin
    using Aqua: test_persistent_tasks
    test_persistent_tasks(CacheVariables)
end

@testitem "Undocumented names" begin
    using Aqua: test_undocumented_names
    test_undocumented_names(CacheVariables)
end
