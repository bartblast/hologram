defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module7 do
  use Hologram.Component

  def template do
    ~H"""
    abc{@x}bcd
    """
  end
end
