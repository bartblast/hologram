defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module1 do
  use Hologram.Component

  def init do
    %{}
  end

  def template do
    ~H"""
    <span>test</span>
    """
  end
end
