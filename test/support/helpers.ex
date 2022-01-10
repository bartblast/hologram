defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Builder, as: TemplateBuilder
  alias Mix.Tasks.Compile.Hologram, as: Task

  @default_app_path Reflection.app_path()

  def build_templates_by_path(path) do
    [pages_path: path, components_path: path, layouts_path: path]
    |> Reflection.list_templatables()
    |> TemplateBuilder.build_all()
  end

  # When compile_templatables/1 test helper is used, the router is recompiled with the pages found in the given app_path.
  # After the tests, the router needs to be recompiled with the default app_path.
  # Also, in such case the tests need to be non-async.
  def compile_templatables(app_path \\ @default_app_path) do
    Task.run(app_path: app_path)
  end
end
