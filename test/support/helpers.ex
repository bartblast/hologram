defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Builder, as: TemplateBuilder
  alias Mix.Tasks.Compile.Hologram, as: Task

  @default_pages_path Reflection.pages_path()

  def build_templates_by_path(path) do
    [pages_path: path, components_path: path, layouts_path: path]
    |> Reflection.list_templatables()
    |> TemplateBuilder.build_all()
  end

  # When compile_pages/1 test helper is used, the router is recompiled with the pages found in the given pages_path.
  # After the tests, the router needs to be recompiled with the default pages_path.
  # Also, in such case the tests need to be non-async.
  def compile_pages(pages_path \\ @default_pages_path) do
    Task.run(pages_path: pages_path)
  end
end
