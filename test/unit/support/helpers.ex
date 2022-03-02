defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Reflection
  alias Hologram.Template.Builder

  @default_app_path Reflection.app_path()

  def build_templates(path \\ @default_app_path) do
    Reflection.list_templatables(app_path: path)
    |> Builder.build_all()
  end

  # When compile_templatables/1 test helper is used, the router is recompiled with the pages found in the given app_path.
  # After the tests, the router needs to be recompiled with the default app_path.
  # Also, in such case the tests need to be non-async.
  def compile_templatables(path \\ @default_app_path) do
    Mix.Tasks.Compile.Hologram.run(app_path: path)
  end

  def md5_hex_regex do
    ~r/^[0-9a-f]{32}$/
  end
end
