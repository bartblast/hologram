alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "build_page_js/8" => fn {graph, module_info_plt, ir_plt, encode_plt, async_mfas,
                             server_callback_analysis_by_templatable, opts} ->
      Compiler.build_page_js(
        Page1,
        graph,
        module_info_plt,
        ir_plt,
        encode_plt,
        async_mfas,
        server_callback_analysis_by_templatable,
        opts
      )
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)

    # Must be computed before remove_manually_ported_mfas/1 strips the Task.await/1 vertex.
    async_mfas = CallGraph.list_async_mfas(call_graph)

    CallGraph.remove_manually_ported_mfas(call_graph)

    runtime_mfas = CallGraph.list_runtime_mfas(call_graph, Reflection.list_pages())
    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)

    graph = CallGraph.get_graph(call_graph_for_pages)
    module_info_plt = CallGraph.module_info_plt(call_graph)
    templatables = Reflection.list_pages() ++ Reflection.list_components()

    server_callback_analysis_by_templatable =
      CallGraph.server_callback_analysis_by_templatable(graph, templatables, module_info_plt)

    runtime_js_binding_modules =
      runtime_mfas
      |> Compiler.list_js_import_modules(ir_plt)
      |> MapSet.new()

    opts = [
      js_dir: Path.join([Reflection.root_dir(), "assets", "js"]),
      runtime_js_binding_modules: runtime_js_binding_modules
    ]

    {graph, module_info_plt, ir_plt, PLT.start(), async_mfas,
     server_callback_analysis_by_templatable, opts}
  end,
  before_each: fn {_graph, _module_info_plt, _ir_plt, encode_plt, _async_mfas,
                   _server_callback_analysis_by_templatable, _opts} = input ->
    # Every iteration starts from an empty encode PLT, the way a compile does.
    PLT.reset(encode_plt)

    input
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_page_js/8", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
