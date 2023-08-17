defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module3 do
  use Hologram.Layout

  @impl Layout
  def template do
    ~H"""
    Module3 template
    """
  end
end
