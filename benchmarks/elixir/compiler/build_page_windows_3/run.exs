alias Hologram.Benchmarks.DataLayer
alias Hologram.Compiler

# What the compile task pays to fold the windows every page downloads, once per compile that
# derives the data layer: each component's window ids derived once from its kept queries, and each
# page's collected from the components its kept reach names. No page is walked and no query is
# extracted here: the data layer keeps both between compiles (see the build_kept_page_reach_3 and
# extract_component_queries_2 benchmarks for what they cost when they are not kept).
#
# The fixtures give it 110 pages. 10 of them reach the two components with a parameterized query
# and hold 12 windows each, 11 of which come from the one query whose entity type is an argument,
# replayed over every entity type of the build. The other 100 reach no query and hold none.
Benchee.run(
  %{
    "build_page_windows/3" => fn {reach_by_page, component_queries, module_info_plt} ->
      Compiler.build_page_windows(reach_by_page, component_queries, module_info_plt)
    end
  },
  # Derived the way a cold compile derives them (see Hologram.Benchmarks.DataLayer).
  before_scenario: fn _input -> DataLayer.kept_inputs() end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_page_windows/3", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
