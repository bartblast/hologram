alias Hologram.Benchmarks.Fixtures.Components.PlainPropComponent
alias Hologram.Benchmarks.Fixtures.Components.QueryPropComponent
alias Hologram.Compiler.QueryExtractor

# The per-component cost the build-time sweep pays once per component the pages reach. The
# parameterized case reads the capture target's IR from its beam file, which is what dominates
# it - the no-capture case is the fast path every component without a query prop takes.
Benchee.run(
  %{
    "parameterized capture" => fn ->
      QueryExtractor.validate_slot_bindings!(QueryPropComponent)
    end,
    "no parameterized captures" => fn ->
      QueryExtractor.validate_slot_bindings!(PlainPropComponent)
    end
  },
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.QueryExtractor.validate_slot_bindings!/1",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
