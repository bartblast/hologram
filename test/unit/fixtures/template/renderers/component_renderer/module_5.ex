defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module5 do
  use Hologram.Component

  def template do
    ~H"""
    <span><slot /></span>
    """
  end
end
