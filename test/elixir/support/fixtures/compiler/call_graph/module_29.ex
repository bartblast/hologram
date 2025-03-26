# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module29 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module30
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module31
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module37

  def init(_params, component, _server) do
    put_state(component,
      ecto_schema: Module30,
      struct_1: %Module31{},
      struct_2: %Module37{}
    )
  end

  def template do
    ~HOLO"Module 29 template"
  end
end
