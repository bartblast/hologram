defmodule Hologram.Test.Fixtures.Compiler.Reflection.Module3 do
  use Hologram.Component

  @impl Component
  def template do
    ~H"""
    Module3 template
    """
  end
end
