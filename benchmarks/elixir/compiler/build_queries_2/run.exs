alias Hologram.Compiler
alias Hologram.Reflection

# Swept outside the measured function because the compile task sweeps once and passes both lists
# down - Hologram.Reflection.list_entities/0 and list_components/0 have benchmarks of their own.
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
