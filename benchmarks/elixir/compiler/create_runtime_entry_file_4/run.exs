alias Hologram.Commons.FileUtils
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "create_runtime_entry_file/4" => fn {runtime_mfas, ir_plt, async_mfas, opts} ->
      Compiler.create_runtime_entry_file(runtime_mfas, ir_plt, async_mfas, opts)
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    async_mfas = CallGraph.list_async_mfas(call_graph)
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph, Reflection.list_pages())

    opts = [
      js_dir: Path.join([Reflection.root_dir(), "assets", "js"]),
      tmp_dir:
        Path.join([Reflection.tmp_dir(), "benchmarks", "compiler", "create_runtime_entry_file_4"])
    ]

    {runtime_mfas, ir_plt, async_mfas, opts}
  end,
  before_each: fn {runtime_mfas, ir_plt, async_mfas, opts} ->
    FileUtils.recreate_dir(opts[:tmp_dir])
    {runtime_mfas, ir_plt, async_mfas, opts}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.create_runtime_entry_file/4",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
