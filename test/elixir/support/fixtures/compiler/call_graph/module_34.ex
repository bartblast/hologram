# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.CallGraph.Module34 do
  use Hologram.Component

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module35
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module36
  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module37

  def init(_params, component, _server) do
    put_state(component,
      ecto_schema: Module35,
      struct_1: %Module36{},
      struct_2: %Module37{}
    )
  end

  def template do
    ~HOLO"Module 34 template"
  end
end
