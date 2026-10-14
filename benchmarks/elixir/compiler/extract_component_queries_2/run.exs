alias Hologram.Compiler
alias Hologram.Reflection

# Listed outside the measured function because the compile task lists both once, from its module
# info PLT, and passes them down.
component_modules = Reflection.list_components()
entity_types = Reflection.list_entities()

# What the compile task pays to extract the registered queries of every component of the build: the
# terms of each from_query prop, the argument names of the parameterized captures and the modules
# the captures point at. A cold compile pays it for every component. A compile that derives the data
# layer pays it only for the components whose queries the edit can have changed, and an edit of an
# entity type, a role or a policy, which can change all of them.
Benchee.run(
  %{
    "extract_component_queries/2" => fn ->
      Compiler.extract_component_queries(component_modules, entity_types)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.extract_component_queries/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
