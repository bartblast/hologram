# TODO: refactor & test

defmodule Hologram.Compiler do
  alias Hologram.Compiler.{
    Builder,
    CallGraph,
    CallGraphBuilder,
    ModuleDefAggregator,
    ModuleDefStore,
    Reflection
  }

  alias Hologram.Template.Builder, as: TemplateBuilder
  alias Hologram.Utils

  def compile(opts) do
    output_path = resolve_output_path()
    File.mkdir_p!(output_path)

    Reflection.root_priv_path()
    |> File.mkdir_p!()

    ModuleDefStore.run()
    CallGraph.run()

    templatables = Reflection.list_templatables(opts)
    templatables = if opts[:templatables], do: templatables ++ opts[:templatables], else: templatables
    templates = TemplateBuilder.build_all(templatables)
    dump_template_store(templates)
    TemplateStore.run()

    pages = Reflection.list_pages(opts)
    dump_page_list(pages)

    module_defs = aggregate_module_defs(pages)
    call_graph = build_call_graph(pages, module_defs, templates)

    build_pages(pages, output_path, module_defs, call_graph)
    |> dump_page_digest_store()

    TemplateStore.stop()
    CallGraph.stop()
    ModuleDefStore.stop()
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

  defp resolve_output_path do
    Reflection.root_path() <> "/priv/static/hologram"
  end
end
