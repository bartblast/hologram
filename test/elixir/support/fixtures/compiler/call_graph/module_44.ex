# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module44 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-callgraph-module44"

  layout Hologram.Test.Fixtures.Compiler.CallGraph.Module15

  def init(_props, component, _server) do
    component
  end

  def template do
    ~HOLO"""
    Module44 template
    """
  end

  def action(:action_44a, _params, component) do
    component
  end
end
