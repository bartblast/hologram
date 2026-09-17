alias Hologram.Benchmarks.Fixtures.Page1
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "build_page_js/5" => fn {mfas, ir_plt, encode_plt, async_mfas, opts} ->
      Compiler.build_page_js(mfas, ir_plt, encode_plt, async_mfas, opts)
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

    mfas =
      CallGraph.list_page_mfas(
        graph,
        Page1,
        server_callback_analysis_by_templatable,
        module_info_plt
      )

    runtime_js_binding_modules =
      runtime_mfas
      |> Compiler.list_js_import_modules(ir_plt, module_info_plt)
      |> MapSet.new()

    opts = [
      js_dir: Path.join([Reflection.root_dir(), "assets", "js"]),
      module_info_plt: module_info_plt,
      module_metadata: Compiler.build_module_metadata(module_info_plt),
      runtime_js_binding_modules: runtime_js_binding_modules
    ]

    {mfas, ir_plt, PLT.start(), async_mfas, opts}
  end,
  before_each: fn {mfas, ir_plt, encode_plt, async_mfas, opts} = input ->
    # A compile encodes the reachable functions of all pages before it renders any page, so every
    # iteration renders from an encode PLT filled for the page, and the encoding is left out of
    # the measurement (encode_reachable_functions_5 measures it).
    PLT.reset(encode_plt)

    Compiler.encode_reachable_functions(
      mfas,
      ir_plt,
      encode_plt,
      async_mfas,
      opts[:module_info_plt]
    )

    input
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.build_page_js/5", file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
