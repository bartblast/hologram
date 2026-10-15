alias Hologram.Commons.FileUtils
alias Hologram.Commons.PLT
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "create_runtime_entry_file/7" => fn {runtime_mfas, ir_plt, encode_plt, async_mfas,
                                         app_versions, sync_constants_js, opts} ->
      Compiler.create_runtime_entry_file(
        runtime_mfas,
        ir_plt,
        encode_plt,
        async_mfas,
        app_versions,
        sync_constants_js,
        opts
      )
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    module_info_plt = CallGraph.module_info_plt(call_graph)
    async_mfas = CallGraph.list_async_mfas(call_graph)
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)
    app_versions = Compiler.build_app_versions(call_graph)

    # The graph still holds the manually ported MFAs here, so one listing answers both what the
    # data layer is compiled with and whether a page checks permissions.
    listed_reach = Compiler.list_reach_by_page(Reflection.list_pages(), call_graph)
    permission_checking_pages = Compiler.pages_checking_permissions(listed_reach)

    reach_by_page =
      Compiler.build_kept_page_reach(listed_reach, permission_checking_pages, module_info_plt)

    component_queries =
      reach_by_page
      |> Enum.flat_map(fn {_page_module, reach} -> reach.components end)
      |> Enum.uniq()
      |> Compiler.extract_component_queries(Reflection.list_entities(module_info_plt), ir_plt)

    sync_constants_js =
      reach_by_page
      |> Compiler.build_sync_constants(component_queries, module_info_plt)
      |> Compiler.build_sync_constants_js()

    opts = [
      js_dir: Path.join([Reflection.root_dir(), "assets", "js"]),
      module_info_plt: module_info_plt,
      module_metadata: Compiler.build_module_metadata(module_info_plt),
      subsystems: [:data_layer],
      tmp_dir:
        Path.join([Reflection.tmp_dir(), "benchmarks", "compiler", "create_runtime_entry_file_7"])
    ]

    {runtime_mfas, ir_plt, PLT.start(), async_mfas, app_versions, sync_constants_js, opts}
  end,
  before_each: fn {runtime_mfas, ir_plt, encode_plt, async_mfas, app_versions, sync_constants_js,
                   opts} ->
    FileUtils.recreate_dir(opts[:tmp_dir])

    # Every iteration starts from an empty encode PLT, the way a compile does.
    PLT.reset(encode_plt)

    {runtime_mfas, ir_plt, encode_plt, async_mfas, app_versions, sync_constants_js, opts}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.create_runtime_entry_file/7",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 10
)
