# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Controller.Module26 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.LayoutFixture

  route "/hologram-test-fixtures-controller-module26"

  layout LayoutFixture

  middleware :enrich

  def enrich(server, _opts) do
    put_stash(server, :marker, "injected_by_middleware")
  end

  @impl Page
  def init(_params, component, server) do
    put_state(component, marker: get_stash(server, :marker))
  end

  @impl Page
  def template do
    ~HOLO"marker={@marker}"
  end
end
