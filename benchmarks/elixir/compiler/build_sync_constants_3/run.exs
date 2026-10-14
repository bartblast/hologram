alias Hologram.Benchmarks.DataLayer
alias Hologram.Compiler

# What the compile task pays to fold what the client's data layer is compiled with, once per
# compile that derives the data layer: the entity types each page's kept modules name, the ones
# the kept queries of every reached component name, and the argument names of the parameterized
# captures. No page is walked and no query is extracted here: the data layer keeps both between
# compiles.
#
# The function lists the entity types from the module info PLT it is given, so the number holds no
# read of the beams.
#
# The fixtures give it 110 pages, 10 of which reach the two components with a parameterized
# query. The result names 11 of the 21 entity types, the ones the argument-entity query fits, and
# the prop params of both components. No page checks permissions, so neither the grant type nor
# the policied types join.
Benchee.run(
  %{
    "build_sync_constants/3" => fn {reach_by_page, component_queries, module_info_plt} ->
      Compiler.build_sync_constants(reach_by_page, component_queries, module_info_plt)
    end
  },
  # Derived the way a cold compile derives them (see Hologram.Benchmarks.DataLayer).
  before_scenario: fn _input -> DataLayer.kept_inputs() end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_sync_constants/3",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
