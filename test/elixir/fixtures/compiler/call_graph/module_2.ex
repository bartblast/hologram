defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module2 do
  use Hologram.Page

  route "/module_2"

  layout Hologram.Test.Fixtures.Compiler.CallGraph.Module3

  def template do
    ~H"""
    Module2 template
    """
  end
end
