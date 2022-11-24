# TODO: refactor & test

defmodule Hologram.Compiler do
  require Logger

  alias Hologram.Compiler.{
    Builder,
    CallGraph,
    CallGraphBuilder,
    ModuleDefAggregator,
    ModuleDefStore,
    Reflection
  }

  alias Hologram.Runtime.TemplateStore
  alias Hologram.Template.Builder, as: TemplateBuilder
  alias Hologram.Utils

  def compile(opts) do
    log_paths()

    output_path = resolve_output_path()
    File.mkdir_p!(output_path)

    Reflection.root_priv_path()
    |> File.mkdir_p!()

    ModuleDefStore.run()
    CallGraph.run()

    templatables = Reflection.list_templatables(opts)

    templatables =
      if opts[:templatables], do: templatables ++ opts[:templatables], else: templatables

    Logger.debug("Hologram: found templatables: #{inspect(templatables)}")

    templates = TemplateBuilder.build_all(templatables)
    dump_template_store(templates)
    TemplateStore.run()

    pages = Reflection.list_pages(opts)
    Logger.debug("Hologram: found pages: #{inspect(pages)}")
    dump_page_list(pages)
    Logger.debug("Hologram: pages dumped")

    module_defs = aggregate_module_defs(pages)
    Logger.debug("Hologram: module defs aggregated")

    call_graph = build_call_graph(pages, module_defs, templates)
    Logger.debug("Hologram: call graph built")

    build_pages(pages, output_path, module_defs, call_graph)
    |> dump_page_digest_store()

    Logger.debug("Hologram: page digest store dumped")

    TemplateStore.stop()
    Logger.debug("Hologram: template store stopped")

    CallGraph.stop()
    ModuleDefStore.stop()

    %{
      call_graph: call_graph,
      module_defs: module_defs,
      pages: pages,
      templatables: templatables,
      templates: templates
    }
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

    // CAUTION: related code is in assets/js/hologram.js
    if (window.hologramRuntimeScriptLoaded && window.hologramPageScriptLoaded && !window.hologramPageMounted) {
      window.hologramPageMounted = true
      Hologram.run(window.hologramArgs)
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

  defp log_paths do
    Logger.debug("Hologram: compile priv path = #{Reflection.root_priv_path()}")
    Logger.debug("Hologram: compile output path = #{resolve_output_path()}")

    Logger.debug(
      "Hologram: page digest store dump path = #{Reflection.root_page_digest_store_path()}"
    )

    Logger.debug("Hologram: template store dump path = #{Reflection.root_template_store_path()}")

    Logger.debug(
      "Hologram: template store load path = #{Reflection.release_template_store_path()}"
    )
  end

  defp resolve_output_path do
    Reflection.root_path() <> "/priv/static/hologram"
  end
end
