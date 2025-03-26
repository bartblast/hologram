defmodule Hologram.Test.Fixtures.Compiler.Module6 do
  use Hologram.Component

  @impl Component
  def template do
    ~HOLO"""
    Module6 template
    """
  end
end
