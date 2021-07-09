defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module1 do
  use Hologram.Component

  def template do
    ~H"""
    <div>test</div>
    """
  end
end
