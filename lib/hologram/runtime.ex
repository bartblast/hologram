# DEFER: test

defmodule Hologram.Runtime do
  alias Hologram.Runtime.{PageDigestStore, RouterBuilder, StaticDigestStore, TemplateStore}

  def reload do
    PageDigestStore.reload()
    StaticDigestStore.reload()
    TemplateStore.reload()
    RouterBuilder.rebuild()
  end

  def run do
    PageDigestStore.run()
    StaticDigestStore.run()
    TemplateStore.run()
    RouterBuilder.run()
  end
end
