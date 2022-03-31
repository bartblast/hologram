# DEFER: test

defmodule Hologram.Runtime do
  alias Hologram.Runtime.{PageDigestStore, TemplateStore}

  def reload do
    PageDigestStore.reload()
    TemplateStore.reload()
  end
end
