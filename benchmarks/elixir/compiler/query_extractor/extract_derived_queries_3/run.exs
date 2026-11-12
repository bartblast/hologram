alias Hologram.Benchmarks.Fixtures.Components.EntityPropComponent
alias Hologram.Benchmarks.Fixtures.Components.PlainPropComponent
alias Hologram.Benchmarks.Fixtures.Components.QueryPropComponent
alias Hologram.Benchmarks.Fixtures.Entity1
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Compiler.QueryExtractor
alias Hologram.Reflection

# Listed once because the build lists the entity types once, from its module info PLT, and passes
# the list down.
all_entity_types = Reflection.list_entities()
one_entity_type = [Entity1]

# Built outside the measured functions because the compile task has every component's IR in its IR
# PLT before the data layer derives, and the extractor reads it from there.
ir_plt =
  Compiler.build_missing_ir!(PLT.start(), [
    EntityPropComponent,
    PlainPropComponent,
    QueryPropComponent
  ])

# The per-component cost the build pays once per component whose queries it extracts. The cases
# with a derived field read its function's IR from the IR PLT and walk it once - the no-field case
# is the fast path every component without a derived field takes.
#
# The two argument-entity cases differ only in how many candidates the recorded stages are
# replayed over, and that is the point: the walk happens ONCE either way, so the gap between them
# is the replay alone. An extractor that went back to re-walking the function's body per candidate
# would not show up in either number on its own - it shows up in the distance between them.
Benchee.run(
  %{
    "no derived fields" => fn ->
      QueryExtractor.extract_derived_queries(PlainPropComponent, all_entity_types, ir_plt)
    end,
    "field naming its entity" => fn ->
      QueryExtractor.extract_derived_queries(QueryPropComponent, all_entity_types, ir_plt)
    end,
    "field whose entity is an argument, 1 candidate" => fn ->
      QueryExtractor.extract_derived_queries(EntityPropComponent, one_entity_type, ir_plt)
    end,
    "field whose entity is an argument, #{length(all_entity_types)} candidates" => fn ->
      QueryExtractor.extract_derived_queries(EntityPropComponent, all_entity_types, ir_plt)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.QueryExtractor.extract_derived_queries/3",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
