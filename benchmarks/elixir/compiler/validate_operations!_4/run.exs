alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Compiler
alias Hologram.Reflection

# Every module's IR is built here, so the measured function reads the IR of the callers it judges
# and builds none: the state of a compile that kept its IR PLT.
ir_plt = Compiler.build_ir_plt()

# The UNSPLIT graph, with the manually ported MFAs still in it: the functions that ask about an
# operation are hand-ported, and it is their callers that are read.
call_graph = Compiler.build_call_graph(ir_plt)

# Swept outside the measured function because the compile task sweeps and passes the list down -
# Hologram.Reflection.list_entities/0 has a benchmark of its own.
entity_types = Reflection.list_entities()

# What the compile task pays to judge the entity operations the build asks about, once per
# compile that derives the data layer: the vocabulary and the role names collected from every
# entity type, the callers of the four asking functions read from the graph, and each caller's
# asks read from its IR.
#
# The two cases are the two scopes a compile judges. Every caller is judged when nothing was kept
# or the vocabulary can have moved. After an edit that leaves the data model alone, only the
# callers in the edited modules are, and the page edited here asks nothing, so that case is the
# vocabulary and the caller listing alone.
#
# The fixtures give it 21 entity types and no asking module of their own: the 5 asks of the build
# are the framework's, from 5 functions in 3 modules.
Benchee.run(
  %{
    "every caller" => fn ->
      Compiler.validate_operations!(entity_types, call_graph, ir_plt)
    end,
    "one edited page" => fn ->
      Compiler.validate_operations!(entity_types, call_graph, ir_plt, modules: [Page1])
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.validate_operations!/4",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
