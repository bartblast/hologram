defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module11 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-callgraph-module11"

  layout Hologram.Test.Fixtures.Compiler.CallGraph.Module3

  @impl Page
  def template do
    ~H"""
    Module11 template
    """
  end
end
