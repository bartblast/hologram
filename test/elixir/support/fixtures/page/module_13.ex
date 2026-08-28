# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Page.Module13 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Entity.Module4

  route "/hologram-test-fixtures-page-module13"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def template do
    ~HOLO"""
    nothing queried here
    """
  end

  # The entity type as a VALUE, the way Entity.new(Module4, ...) and Entity.validate(Module4, ...)
  # hand one over, and the way a page choosing a type to work with holds one. Nothing here calls a
  # function of Module4 and no query anywhere reads it, so the only thing that can put it in the
  # client's model is this mention - which reaches it because the call graph links a mentioned
  # module to its own __struct__/0 and __struct__/1.
  @impl Page
  def action(:choose_entity_type, _params, component) do
    put_state(component, :entity_type, Module4)
  end
end
