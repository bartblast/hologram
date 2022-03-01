defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module5 do
  use Hologram.Component

  def init do
    %{}
  end

  def template do
    ~H"""
    <h1>h1 node</h1>
    <slot />
    <p>p node</p>
    """
  end
end
