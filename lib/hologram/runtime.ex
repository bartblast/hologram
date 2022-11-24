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
    PageDigestStore.run(path: opts[:page_digest_store_path])
    StaticDigestStore.run(path: opts[:static_digest_store_path])
    TemplateStore.run(path: opts[:template_store_path])
    RouterBuilder.run()
  end
end
