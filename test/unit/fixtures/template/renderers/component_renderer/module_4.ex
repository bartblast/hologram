defmodule Hologram.Test.Fixtures.Template.ComponentRenderer.Module4 do
  use Hologram.Component

  def init do
    %{}
  end

  def template do
    ~H"""
    <div>div node</div>
    <slot />
    <span>span node</span>
    """
  end
end
