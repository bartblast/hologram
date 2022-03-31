# DEFER: test

defmodule Hologram.Runtime do
  alias Hologram.Runtime.{PageDigestStore, StaticDigestStore, TemplateStore}

  def reload do
    PageDigestStore.reload()
    StaticDigestStore.reload()
    TemplateStore.reload()
  end

  def run do
    PageDigestStore.run()
    StaticDigestStore.run()
    TemplateStore.run()
  end
end
