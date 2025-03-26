# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module26 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module27
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module28
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module29

  def init(_params, component, _server) do
    put_state(component,
      ecto_schema: Module27,
      struct: %Module28{}
    )
  end

  def template do
    ~HOLO"""
    <Module29 cid="component_29" />
    """
  end
end
