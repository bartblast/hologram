defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module2 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-callgraph-module2"

  layout Hologram.Test.Fixtures.Compiler.CallGraph.Module3

  @impl Page
  def template do
    ~HOLO"""
    Module2 template
    """
  end
end
