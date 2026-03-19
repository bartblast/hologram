# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module47 do
  use Hologram.Page

  alias Module46

  route "/hologram-test-fixtures-compiler-callgraph-module47"

  layout Hologram.Test.Fixtures.Compiler.CallGraph.Module15

  def template do
    ~HOLO"""
    Module47 template
    """
  end

  def action(:action_47a, _params, component) do
    Module46.init(1, 2, 3)
    component
  end
end
