defmodule Hologram.Test.Fixtures.Commons.Reflection.Module3 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    Module3 template
    """
  end
end
