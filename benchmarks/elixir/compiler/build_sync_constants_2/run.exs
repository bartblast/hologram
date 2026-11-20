alias Hologram.Benchmarks.DataLayer
alias Hologram.Compiler

# What the compile task pays to fold what the client's data layer is compiled with, once per
# compile that derives the data layer: the entity types each page's kept modules name and the ones
# they lead to by the names the page's kept atoms spell. No page is walked here: the data layer
# keeps its reach between compiles.
#
# The function lists the entity types from the module info PLT it is given, so the number holds no
# read of the beams.
#
# The fixtures give it every page of the suite. The result names the entity types the pages mention
# and the ones their spelled names lead to, with the grant type, the policied types and the types
# they lead to, which every build with a data model bakes, the hash of every type's rules, and the
# share of the synced types each page fills first.
Benchee.run(
  %{
    "build_sync_constants/2" => fn {reach_by_page, _component_queries, module_info_plt} ->
      Compiler.build_sync_constants(reach_by_page, module_info_plt)
    end
  },
  # Derived the way a cold compile derives them (see Hologram.Benchmarks.DataLayer).
  before_scenario: fn _input -> DataLayer.kept_inputs() end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_sync_constants/2",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
