# credo:disable-for-this-file Credo.Check.Refactor.ABCSize
defmodule Mix.Tasks.Compile.Hologram do
  @moduledoc """
  Builds Hologram project JavaScript bundles, the call graph of the code,
  PLTs needed by the runtime and PLTs needed to speed up future compilation.
  """

  use Mix.Task.Compiler

  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.Compiler.CallGraph
  alias Hologram.Reflection

  require Logger

  @impl Mix.Task.Compiler
  # If the options are strings, it means that the task was executed directly by the Elixir compiler.
  def run([hd | _tail]) when is_binary(hd) do
    opts = build_default_opts()

    if elixir_ls_build?(opts) do
      :ok
    else
      run(opts)
    end
  end

  @impl Mix.Task.Compiler
  def run([]) do
    run(build_default_opts())
  end

  @doc """
  Benchmarks: https://github.com/bartblast/hologram/blob/master/benchmarks/mix/tasks/compile.hologram/README.md
  """
  @impl Mix.Task.Compiler
  def run(opts) do
    Logger.info("Hologram: compiler started")

    assets_dir = opts[:assets_dir]
    build_dir = opts[:build_dir]

    File.mkdir_p!(build_dir)
    File.mkdir_p!(opts[:static_dir])
    File.mkdir_p!(opts[:tmp_dir])

    Compiler.maybe_install_js_deps(assets_dir, build_dir)

    {module_beam_path_plt, module_beam_path_plt_dump_path} =
      Compiler.maybe_load_module_beam_path_plt(build_dir)

    # Building IR PLT from scratch is almost x2 faster than loading IR PLT from a dump file,
    # so Compiler.build_ir_plt/1 is used instead of Compiler.maybe_load_ir_plt/1 + Compiler.patch_ir_plt!/3.
    ir_plt = Compiler.build_ir_plt(module_beam_path_plt)

    # Patching call graph for 1 updated module takes ~100-400 ms, so it's too long if there are multiple updates
    # (and one needs to take into account that the graph has to be loaded first and dumped at the end).
    # Building call graph from scratch is more predictable as it takes ~563 ms for ~1300 modules.
    call_graph_for_runtime =
      ir_plt
      |> Compiler.build_call_graph()
      # DEFER: In case the list of manually ported MFAs grows to ~32 vertices,
      # consider using similar strategy to CallGraph.remove_runtime_mfas!/2,
      # e.g. implement opts param for CallGraph.remove_vertices/2 to allow rebuilding the graph.
      |> CallGraph.remove_manually_ported_mfas()

    runtime_mfas = CallGraph.list_runtime_mfas(call_graph_for_runtime)

    runtime_entry_file_path = Compiler.create_runtime_entry_file(runtime_mfas, ir_plt, opts)

    page_modules = Reflection.list_pages()

    Compiler.validate_page_modules(page_modules)

    call_graph_for_pages = CallGraph.remove_runtime_mfas!(call_graph_for_runtime, runtime_mfas)

    page_entry_files_info =
      page_modules
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

    old_build_static_artifacts =
      opts[:static_dir]
      |> File.ls!()
      |> Enum.map(fn file_name -> Path.join(opts[:static_dir], file_name) end)

    bundles_info = Compiler.bundle(entry_files_info, opts)

    new_build_static_artifacts =
      Enum.reduce(bundles_info, [], fn bundle_info, acc ->
        [bundle_info.static_bundle_path, bundle_info.static_source_map_path | acc]
      end)

    {page_digest_plt, page_digest_plt_dump_path} =
      Compiler.build_page_digest_plt(bundles_info, opts)

    PLT.dump(page_digest_plt, page_digest_plt_dump_path)
    PLT.dump(module_beam_path_plt, module_beam_path_plt_dump_path)

    Enum.each(old_build_static_artifacts -- new_build_static_artifacts, &File.rm!/1)

    Logger.info("Hologram: compiler finished")

    :ok
  end

  defp build_default_opts do
    root_dir = Reflection.root_dir()
    assets_dir = Path.join([root_dir, "deps", "hologram", "assets"])
    build_dir = Reflection.build_dir()
    node_modules_path = Path.join(assets_dir, "node_modules")

    [
      assets_dir: assets_dir,
      build_dir: build_dir,
      esbuild_bin_path: Path.join([node_modules_path, ".bin", "esbuild"]),
      # Biome is almost x20 faster than Prettier in Hologram benchmarks
      formatter_bin_path: Path.join([node_modules_path, ".bin", "biome"]),
      js_dir: Path.join(assets_dir, "js"),
      static_dir: Path.join([root_dir, "priv", "static", "hologram"]),
      tmp_dir: Path.join(build_dir, "tmp")
    ]
  end

  defp elixir_ls_build?(opts) do
    String.contains?(opts[:build_dir], "/.elixir_ls/")
  end
end
