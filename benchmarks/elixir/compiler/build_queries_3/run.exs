alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Reflection

# Listed outside the measured function because the compile task lists the entity types once, from
# its module info PLT, and keeps the extracted queries between compiles (see the
# extract_component_queries_3 benchmark for what an extraction costs).
entity_types = Reflection.list_entities()

component_queries =
  Compiler.extract_component_queries(Reflection.list_components(), entity_types, PLT.start())

# What the compile task pays to derive everything a running app holds about registered queries from
# the extracted queries of every component, once per compile that derives the data layer: the three
# validations run over them, the registry built, the windows derived and the prop params indexed.
# Measured for a build with a page checking permissions on the client, the one whose windows also
# embed the related rows every queried type's rules read.
Benchee.run(
  %{
    "build_queries/3" => fn ->
      Compiler.build_queries(component_queries, entity_types, true)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_queries/3", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
