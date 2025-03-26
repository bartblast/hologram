# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module23 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module32
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module33
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module34

  def init(_params, component, _server) do
    put_state(component,
      ecto_schema: Module32,
      struct: %Module33{},
      duplicate_ecto_schema: Module32
    )
  end

  def template do
    ~HOLO"""
    <Module34 cid="component_34" />
    """
  end
end
