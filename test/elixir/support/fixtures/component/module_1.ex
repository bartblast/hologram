defmodule Hologram.Test.Fixtures.Component.Module1 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    Module1 template
    """
  end
end
