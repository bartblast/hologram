defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler.Reflection
  alias Hologram.Runtime.TemplateStore
  alias Hologram.Template.Builder

  @default_app_path Reflection.app_path()

  def build_templates(path \\ @default_app_path) do
    Reflection.list_templatables(app_path: path)
    |> Builder.build_all()
  end

  def compile(opts \\ []) do
    Mix.Tasks.Compile.Hologram.run(opts)
  end

  def md5_hex_regex do
    ~r/^[0-9a-f]{32}$/
  end

  def seed_template_store(modules) do
    modules
    |> Builder.build_all()
    |> Enum.each(fn {module, template} -> TemplateStore.put(module, template) end)
  end
end
