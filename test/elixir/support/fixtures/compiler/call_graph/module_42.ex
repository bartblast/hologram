# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module42 do
  use Hologram.Page

  route "/hologram-test-fixtures-compiler-callgraph-module42"

  layout Hologram.Test.Fixtures.Compiler.CallGraph.Module15

  def template do
    ~HOLO"""
    Module42 template
    """
  end

  def command(:command_42a, _params, server) do
    server
  end
end
