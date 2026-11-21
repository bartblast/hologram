# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Page4 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity2
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol

  route "/hologram-test-fixtures-compiler-impl-reach-page4"

  layout Hologram.Test.Fixtures.LayoutFixture

  state :value, :any

  derived :result, :any, fn value -> Protocol.run(value) end

  @impl Page
  def init(_params, component, _server) do
    put_state(component, :value, %Entity2{})
  end

  @impl Page
  def template do
    ~HOLO"""
    nothing read here
    """
  end
end
