defmodule Hologram.Runtime do
  alias Hologram.Runtime.PageDigestStore
  alias Hologram.Runtime.RouterBuilder
  alias Hologram.Runtime.StaticDigestStore
  alias Hologram.Runtime.TemplateStore

  # TODO: test
  def reload do
    PageDigestStore.reload()
    StaticDigestStore.reload()
    TemplateStore.reload()
    RouterBuilder.rebuild()
  end

  def reload_module(module) do
    IEx.Helpers.r(module)
  end

  # TODO: test
  def run(opts \\ []) do
    PageDigestStore.run()
    StaticDigestStore.run()
    TemplateStore.run(file_path: opts[:template_store_file_path])
    RouterBuilder.run()
  end
end
