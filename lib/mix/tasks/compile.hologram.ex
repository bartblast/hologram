# DEFER: refactor & test

defmodule Mix.Tasks.Compile.Hologram do
  use Mix.Task.Compiler
  require Logger

  alias Hologram.{MixProject, Utils}

  alias Hologram.Compiler.{
    Builder,
    CallGraph,
    CallGraphBuilder,
    ModuleDefAggregator,
    ModuleDefStore,
    Reflection
  }

  alias Hologram.Template.Builder, as: TemplateBuilder
  @root_path Reflection.root_path()

  def run(opts \\ []) do
    if has_source?() do
      source_digest =
        list_source_files(opts)
        |> digest_files()

      if !has_source_digest?() || has_source_changes?(source_digest) do
        compile(opts)
        save_source_digest(source_digest)
      end
    end

    :ok
  end

  defp compile(opts) do
    Logger.debug("Hologram compiler started")

    output_path = resolve_output_path()
    File.mkdir_p!(output_path)

    Reflection.root_priv_path()
    |> File.mkdir_p!()

    ModuleDefStore.create()
    CallGraph.create()

    templatables = Reflection.list_templatables(opts)
    templates = TemplateBuilder.build_all(templatables)
    dump_template_store(templates)

    pages = Reflection.list_pages(opts)
    dump_page_list(pages)

    module_defs = aggregate_module_defs(pages)
    call_graph = build_call_graph(pages, module_defs, templates)

    build_pages(pages, output_path, module_defs, call_graph)
    |> dump_page_digest_store()

    CallGraph.destroy()
    ModuleDefStore.destroy()

    Logger.debug("Hologram compiler finished")
  end

  defp aggregate_module_defs(pages) do
    pages
    |> Utils.map_async(&ModuleDefAggregator.aggregate/1)
    |> Utils.await_tasks()

    ModuleDefStore.get_all()
  end

  defp build_call_graph(pages, module_defs, templates) do
    pages
    |> Utils.map_async(&CallGraphBuilder.build(&1, module_defs, templates, nil))
    |> Utils.await_tasks()

    CallGraph.get()
  end

  defp build_page(page, output_path, module_defs, call_graph) do
    js = Builder.build(page, module_defs, call_graph)

    output = """
    "use strict";

    #{js}

    window.hologramPageScriptLoaded = true;

    if (window.hologramRuntimeScriptLoaded && window.hologramPageScriptLoaded && !window.hologramPageMounted) {
      window.hologramPageMounted = true
      Hologram.run(window.hologramArgs.class, window.hologramArgs.state)
    }
    """

    digest =
      :crypto.hash(:md5, output)
      |> Base.encode16()
      |> String.downcase()

    "#{output_path}/page-#{digest}.js"
    |> File.write!(output)

    {page, digest}
  end

  defp build_pages(pages, output_path, module_defs, call_graph) do
    pages
    |> Utils.map_async(&build_page(&1, output_path, module_defs, call_graph))
    |> Utils.await_tasks()
  end

  defp digest_files(paths) do
    data =
      Enum.reduce(paths, [], &(&2 ++ Utils.list_files_recursively(&1)))
      |> Enum.reduce(%{}, &Map.put(&2, &1, File.read!(&1)))
      |> :erlang.term_to_binary()

    :crypto.hash(:md5, data)
  end

  defp dump_page_digest_store(page_digests) do
    data =
      page_digests
      |> Utils.serialize()

    Reflection.root_page_digest_store_path()
    |> File.write!(data)
  end

  defp dump_page_list(pages) do
    data = Utils.serialize(pages)

    Reflection.root_page_list_path()
    |> File.write!(data)
  end

  defp dump_template_store(templates) do
    data = Utils.serialize(templates)

    Reflection.root_template_store_path()
    |> File.write!(data)
  end

  defp has_source? do
    Reflection.mix_path()
    |> File.exists?()
  end

  defp has_source_changes?(new_source_digest) do
    old_source_digest =
      Reflection.root_source_digest_path()
      |> File.read!()

    new_source_digest != old_source_digest
  end

  defp has_source_digest? do
    Reflection.root_source_digest_path()
    |> File.exists?()
  end

  defp list_source_files(opts) do
    [
      Reflection.app_path(opts),
      Reflection.lib_path(opts),
      Reflection.mix_path(opts),
      Reflection.mix_lock_path(opts)
    ]
  end

  defp resolve_output_path do
    if MixProject.is_dep?() do
      "#{@root_path}/../../priv/static/hologram"
    else
      "#{@root_path}/priv/static/hologram"
    end
  end

  defp save_source_digest(source_digest) do
    Reflection.root_source_digest_path()
    |> File.write!(source_digest)
  end
end
