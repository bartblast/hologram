alias Hologram.Commons.FileUtils
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "bundle/2" => fn {entry_files_info, opts} ->
      Compiler.bundle(entry_files_info, opts)
    end
  },
  before_scenario: fn _input ->
    assets_dir = Path.join(Reflection.root_dir(), "assets")
    node_modules_path = Path.join(assets_dir, "node_modules")
    tmp_dir = Path.join([Reflection.tmp_dir(), "benchmarks", "compiler", "bundle_2"])

    opts = [
      esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
      formatter_bin_path: Path.join([node_modules_path, ".bin", "biome"]),
      js_dir: Path.join([assets_dir, "js"]),
      tmp_dir: tmp_dir,
      static_dir: Path.join(tmp_dir, "static")
    ]

    FileUtils.recreate_dir(opts[:tmp_dir])
    File.mkdir!(opts[:static_dir])

    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)
    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)

    runtime_entry_file_path = Compiler.create_runtime_entry_file(runtime_mfas, ir_plt, opts)

    page_entry_files_info =
      Reflection.list_pages()
      |> Compiler.create_page_entry_files(call_graph_for_pages, ir_plt, opts)
      |> Enum.map(fn {entry_name, entry_file_path} ->
        {entry_name, entry_file_path, "page"}
      end)

    page_entry_file_paths =
      Enum.map(page_entry_files_info, fn {_entry_name, entry_file_path, _bundle_name} ->
        entry_file_path
      end)

    Compiler.format_files([runtime_entry_file_path | page_entry_file_paths], opts)

    entry_files_info = [{"runtime", runtime_entry_file_path, "runtime"} | page_entry_files_info]

    {entry_files_info, opts}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.bundle/2", file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
