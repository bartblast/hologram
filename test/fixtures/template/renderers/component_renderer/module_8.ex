defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module8 do
  use Hologram.Component

  def template do
    ~H"""
    abc{@context.x}bcd
    """
  end
end
