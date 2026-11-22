# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Page3 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity1
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol

  route "/hologram-test-fixtures-compiler-impl-reach-page3"

  layout Hologram.Test.Fixtures.LayoutFixture

  state :value, :any

  derived :result, :any, fn value -> Protocol.run(value) end

  @impl Page
  def init(_params, component, _server) do
    put_state(component, :value, %Entity1{})
  end

  @impl Page
  def template do
    ~HOLO"""
    nothing read here
    """
  end
end
