defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Builder, as: TemplateBuilder
  alias Mix.Tasks.Compile.Hologram, as: Task

  @default_app_path Reflection.app_path()

  def build_templates(path \\ @default_app_path) do
    Reflection.list_templatables(app_path: path)
    |> TemplateBuilder.build_all()
  end

  # When compile_templatables/1 test helper is used, the router is recompiled with the pages found in the given app_path.
  # After the tests, the router needs to be recompiled with the default app_path.
  # Also, in such case the tests need to be non-async.
  def compile_templatables(path \\ @default_app_path) do
    Task.run(app_path: path)
  end
end
