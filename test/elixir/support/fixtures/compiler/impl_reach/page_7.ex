# credo:disable-for-this-file Credo.Check.Readability.Specs
# A page holding Entity7 only through the relationship name it includes.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Page7 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity6
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol

  route "/hologram-test-fixtures-compiler-impl-reach-page7"

  layout Hologram.Test.Fixtures.LayoutFixture

  state :value, :any

  derived :rows, [Entity6], fn -> include(Entity6, target) end

  derived :result, :any, fn value -> Protocol.run(value) end

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
