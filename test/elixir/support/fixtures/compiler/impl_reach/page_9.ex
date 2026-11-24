# credo:disable-for-this-file Credo.Check.Readability.Specs
# A page holding Entity13's date field, which dispatches a protocol on a value it can't name.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Page9 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity13
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol5

  route "/hologram-test-fixtures-compiler-impl-reach-page9"

  layout Hologram.Test.Fixtures.LayoutFixture

  state :value, :any

  derived :rows, [Entity13], fn -> filter(Entity13, label == "shown") end

  derived :result, :any, fn value -> Protocol5.run(value) end

  @impl Page
  def init(_params, component, _server) do
    put_state(component, :value, nil)
  end

  @impl Page
  def template do
    ~HOLO"""
    nothing read here
    """
  end
end
