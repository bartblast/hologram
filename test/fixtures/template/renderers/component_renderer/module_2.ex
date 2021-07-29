defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module2 do
  use Hologram.Component

  def template do
    ~H"""
    <div><Hologram.Test.Fixtures.Template.ComponentRenderer.Module1 /></div>
    """
  end
end
