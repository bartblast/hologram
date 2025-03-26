defmodule Hologram.Test.Fixtures.Reflection.Module3 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    Module3 template
    """
  end
end
