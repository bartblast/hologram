# DEFER: test

defmodule Hologram.Runtime do
  alias Hologram.Runtime.{PageDigestStore, TemplateStore}

  def reload do
    PageDigestStore.populate_table()
    TemplateStore.populate_table()
  end
end
