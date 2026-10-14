alias Hologram.Compiler
alias Hologram.Reflection

# Listed outside the measured function because the compile task lists the entity types once, from
# its module info PLT, and keeps the extracted queries between compiles (see the
# extract_component_queries_2 benchmark for what an extraction costs).
entity_types = Reflection.list_entities()

component_queries = Compiler.extract_component_queries(Reflection.list_components(), entity_types)

# What the compile task pays to derive everything a running app holds about registered queries from
# the extracted queries of every component, once per compile that derives the data layer: the three
# validations run over them, the registry built, the windows derived and the prop params indexed.
Benchee.run(
  %{
    "build_queries/2" => fn ->
      Compiler.build_queries(component_queries, entity_types)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_queries/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
