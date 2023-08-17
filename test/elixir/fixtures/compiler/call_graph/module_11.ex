defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module11 do
  use Hologram.Page

  route "/module_11"

  layout Hologram.Test.Fixtures.Compiler.CallGraph.Module3

  def template do
    ~H"""
    Module11 template
    """
  end
end
