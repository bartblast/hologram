# credo:disable-for-this-file Credo.Check.Readability.Specs
# Page7 with a plain struct whose implementation calls a protocol nothing else on the page calls.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Page8 do
  use Hologram.Page
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity6
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Struct5

  route "/hologram-test-fixtures-compiler-impl-reach-page8"

  layout Hologram.Test.Fixtures.LayoutFixture

  state :value, :any

  derived :rows, [Entity6], fn -> include(Entity6, target) end

  derived :result, :any, fn value -> Protocol.run(value) end

  derived :other, :any, fn -> Protocol.run(%Struct5{}) end

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
