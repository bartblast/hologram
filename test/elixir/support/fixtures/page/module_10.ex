# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Page.Module10 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Entity.Module2

  route "/hologram-test-fixtures-page-module10"

  layout Hologram.Test.Fixtures.LayoutFixture

  @impl Page
  def init(_params, component, _server) do
    put_state(component, :entity, %Module2{})
  end

  # Checked in the TEMPLATE, so the check ships to the client and its grant rows have to be
  # there for it to answer.
  @impl Page
  def template do
    ~HOLO"""
    {can?(nil, :read, @entity)}
    """
  end
end
