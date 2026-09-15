alias Hologram.Commons.FileUtils
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "create_runtime_entry_file/6" => fn {runtime_mfas, ir_plt, encode_plt, async_mfas,
                                         app_versions, opts} ->
      Compiler.create_runtime_entry_file(
        runtime_mfas,
        ir_plt,
        encode_plt,
        async_mfas,
        app_versions,
        opts
      )
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    async_mfas = CallGraph.list_async_mfas(call_graph)
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph, Reflection.list_pages())
    app_versions = Compiler.build_app_versions(call_graph)

    opts = [
      js_dir: Path.join([Reflection.root_dir(), "assets", "js"]),
      tmp_dir:
        Path.join([Reflection.tmp_dir(), "benchmarks", "compiler", "create_runtime_entry_file_6"])
    ]

    {runtime_mfas, ir_plt, PLT.start(), async_mfas, app_versions, opts}
  end,
  before_each: fn {runtime_mfas, ir_plt, encode_plt, async_mfas, app_versions, opts} ->
    FileUtils.recreate_dir(opts[:tmp_dir])

    # Every iteration starts from an empty encode PLT, the way a compile does.
    PLT.reset(encode_plt)

    {runtime_mfas, ir_plt, encode_plt, async_mfas, app_versions, opts}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.create_runtime_entry_file/6",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
