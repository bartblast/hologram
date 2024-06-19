alias Hologram.Commons.FileUtils
alias Hologram.Compiler
alias Hologram.Compiler.CallGraph
alias Hologram.Reflection

Benchee.run(
  %{
    "create_page_entry_files/4" => fn {page_modules, call_graph, ir_plt, opts} ->
      Compiler.create_page_entry_files(page_modules, call_graph, ir_plt, opts)
    end
  },
  before_scenario: fn _input ->
    ir_plt = Compiler.build_ir_plt()
    call_graph = Compiler.build_call_graph(ir_plt)
    runtime_mfas = CallGraph.list_runtime_mfas(call_graph)
    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph, runtime_mfas)

    page_modules = Reflection.list_pages()

    opts = [
      js_dir: Path.join([Reflection.root_dir(), "assets", "js"]),
      tmp_dir:
        Path.join([Reflection.tmp_dir(), "benchmarks", "compiler", "create_page_entry_files_4"])
    ]

    {page_modules, call_graph_for_pages, ir_plt, opts}
  end,
  before_each: fn {page_modules, call_graph, ir_plt, opts} ->
    FileUtils.recreate_dir(opts[:tmp_dir])
    {page_modules, call_graph, ir_plt, opts}
  end,
  formatters: [
    Benchee.Formatters.Console,
    {Benchee.Formatters.Markdown,
     description: "Hologram.Compiler.create_page_entry_files/4",
     file: Path.join(__DIR__, "README.md")}
  ],
  time: 60
)
