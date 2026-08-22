alias Hologram.Benchmarks.Fixtures.Components.EntityPropComponent
alias Hologram.Benchmarks.Fixtures.Components.PlainPropComponent
alias Hologram.Benchmarks.Fixtures.Components.QueryPropComponent
alias Hologram.Benchmarks.Fixtures.Entity1
alias Hologram.Compiler.QueryExtractor
alias Hologram.Reflection

# Swept once because the build sweeps once and passes the list down -
# Hologram.Reflection.list_entities/0 has a benchmark of its own.
all_entity_types = Reflection.list_entities()
one_entity_type = [Entity1]

# The per-component cost the build pays once per component the pages reach. The parameterized
# cases decode the capture target's IR from its beam file and walk it once, which is what
# dominates them - the no-capture case is the fast path every component without a query prop
# takes.
#
# The two argument-entity cases differ only in how many candidates the recorded stages are
# replayed over, and that is the point: the walk happens ONCE either way, so the gap between them
# is the replay alone. An extractor that went back to re-walking the capture's body per candidate
# would not show up in either number on its own - it shows up in the distance between them.
Benchee.run(
  %{
    "no parameterized captures" => fn ->
      QueryExtractor.extract_module_queries(PlainPropComponent, all_entity_types)
    end,
    "capture naming its entity" => fn ->
      QueryExtractor.extract_module_queries(QueryPropComponent, all_entity_types)
    end,
    "capture whose entity is an argument, 1 candidate" => fn ->
      QueryExtractor.extract_module_queries(EntityPropComponent, one_entity_type)
    end,
    "capture whose entity is an argument, #{length(all_entity_types)} candidates" => fn ->
      QueryExtractor.extract_module_queries(EntityPropComponent, all_entity_types)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.QueryExtractor.extract_module_queries/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
