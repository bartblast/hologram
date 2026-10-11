# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mix.Tasks.Holo.Compiler.PageExFunSizes.Module2 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Compiler.CallGraph.Module24

  route "/hologram-test-fixtures-mix-tasks-holo-compiler-pageexfilesizes-module2"

  layout Hologram.Test.Fixtures.LayoutFixture

  # The client code names no reflection function of the Ecto schema the state holds.
  def init(_params, component, _server) do
    put_state(component, ecto_schema: Module24)
  end

  @impl Page
  def template do
    ~HOLO"""
    Module2 template
    """
  end
end
