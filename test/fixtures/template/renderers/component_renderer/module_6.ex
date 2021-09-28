defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module6 do
  use Hologram.Layout

  def template do
    ~H"""
    abc{@x}bcd
    """
  end
end
