# DEFER: test

defmodule Hologram.Runtime do
  alias Hologram.Runtime.{PageDigestStore, TemplateStore}

  def reload do
    PageDigestStore.clean_table()
    PageDigestStore.populate_table()

    TemplateStore.clean_table()
    TemplateStore.populate_table()
  end
end
