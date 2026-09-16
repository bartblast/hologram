alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "encode_reachable_functions/4" => fn {mfas, ir_plt, encode_plt, async_mfas} ->
      Compiler.encode_reachable_functions(mfas, ir_plt, encode_plt, async_mfas)
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)

    # Must be computed before remove_manually_ported_mfas/1 strips the Task.await/1 vertex.
    async_mfas = CallGraph.list_async_mfas(call_graph)

    CallGraph.remove_manually_ported_mfas(call_graph)

    page_modules = Reflection.list_pages()
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph, page_modules)
    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)

    graph = CallGraph.get_graph(call_graph_for_pages)
    module_info_plt = CallGraph.module_info_plt(call_graph)
    templatables = page_modules ++ Reflection.list_components()

    server_callback_analysis_by_templatable =
      CallGraph.server_callback_analysis_by_templatable(graph, templatables, module_info_plt)

    # The MFAs of every page, repeats included, the way the page entry files hand them over.
    mfas =
      Enum.flat_map(page_modules, fn page_module ->
        CallGraph.list_page_mfas(
          graph,
          page_module,
          server_callback_analysis_by_templatable,
          module_info_plt
        )
      end)

    {mfas, ir_plt, PLT.start(), async_mfas}
  end,
  before_each: fn {_mfas, _ir_plt, encode_plt, _async_mfas} = input ->
    # Every iteration starts from an empty encode PLT, the way a compile does.
    PLT.reset(encode_plt)

    input
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.encode_reachable_functions/4",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
