alias Hologram.Compiler
alias Hologram.Reflection

# Listed outside the measured function because the compile task lists both once, from its module
# info PLT, and passes them down.
component_modules = Reflection.list_components()
entity_types = Reflection.list_entities()

# What the compile task pays to collect everything a running app holds about registered queries:
# every component's queries extracted, both validations run over them, the registry built, and the
# windows derived. Until this became a build artifact the SAME work ran again on every boot and
# every live reload, which is what the dump exists to stop.
Benchee.run(
  %{
    "build_queries/2" => fn ->
      Compiler.build_queries(component_modules, entity_types)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_queries/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
