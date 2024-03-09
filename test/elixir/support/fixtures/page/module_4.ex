defmodule Hologram.Test.Fixtures.Page.Module4 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    Module4 template
    """
  end
end
