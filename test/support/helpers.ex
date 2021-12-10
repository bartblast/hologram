defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Builder, as: TemplateBuilder
  alias Hologram.Utils
  alias Mix.Tasks.Compile.Hologram, as: Task

  @default_pages_path Reflection.pages_path()

  def build_templates_by_path(path) do
    pages = Reflection.list_pages(pages_path: path)
    components = Reflection.list_components(components_path: path)
    layouts = Reflection.list_layouts(layouts_path: path)

    # DEFER: consider - this code is very similar to Mix.Tasks.Compile.Hologram.build_templates/1
    pages ++ components ++ layouts
    |> Utils.map_async(&{&1, TemplateBuilder.build(&1)})
    |> Utils.await_tasks()
    |> Enum.into(%{})
  end

  # When compile_pages/1 test helper is used, the router is recompiled with the pages found in the given pages_path.
  # After the tests, the router needs to be recompiled with the default pages_path.
  # Also, in such case the tests need to be non-async.
  def compile_pages(pages_path \\ @default_pages_path) do
    Task.run(pages_path: pages_path)
  end
end
