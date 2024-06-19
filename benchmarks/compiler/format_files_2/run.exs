alias Hologram.Commons.FileUtils
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "format_files/2" => fn {file_paths, opts} ->
      Compiler.format_files(file_paths, opts)
    end
  },
  before_scenario: fn _input ->
    assets_dir = Path.join(Reflection.root_dir(), "assets")

    opts = [
      formatter_bin_path: Path.join([assets_dir, "node_modules", ".bin", "biome"]),
      js_dir: Path.join(assets_dir, "js"),
      tmp_dir: Path.join([Reflection.tmp_dir(), "benchmarks", "compiler", "format_files_2"])
    ]

    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)
    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)
    page_modules = Reflection.list_pages()

    {opts, ir_plt, runtime_mfas, call_graph_for_pages, page_modules}
  end,
  before_each: fn {opts, ir_plt, runtime_mfas, call_graph_for_pages, page_modules} ->
    FileUtils.recreate_dir(opts[:tmp_dir])

    runtime_entry_file_path = Compiler.create_runtime_entry_file(runtime_mfas, ir_plt, opts)

    page_entry_files_info =
      Compiler.create_page_entry_files(page_modules, call_graph_for_pages, ir_plt, opts)

    page_entry_file_paths =
      Enum.map(page_entry_files_info, fn {_entry_name, entry_file_path} -> entry_file_path end)

    file_paths = [runtime_entry_file_path | page_entry_file_paths]

    {file_paths, opts}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.format_files/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
