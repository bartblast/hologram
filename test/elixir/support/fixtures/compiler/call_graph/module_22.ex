# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module22 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module23
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module24
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module25
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module26

  route "/hologram-test-fixtures-compiler-callgraph-module22"

  layout Module23

  def init(_params, component, _server) do
    put_state(component,
      ecto_schema: Module24,
      struct: %Module25{}
    )
  end

  def template do
    ~HOLO"""
    <Module26 cid="component_26" />
    """
  end
end
