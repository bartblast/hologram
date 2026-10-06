# The scenario on this page verifies that a field taken out of a struct server code builds brings
# only what that field holds: the struct in another field loads none of its chunks, which is where
# its protocol implementations live. Client-reachable code on this page (template, actions) must
# not reference the struct fixtures, otherwise the page preloads their chunks and the scenario
# silently stops testing what the server code hands to the client.
defmodule HologramFeatureTests.CallGraph.StructFieldPage do
  use Hologram.Page

  alias HologramFeatureTests.StructFieldFixture
  alias HologramFeatureTests.StructFieldNoteFixture

  route "/call-graph/struct-field"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    fixture = %StructFieldFixture{note: %StructFieldNoteFixture{}}

    put_state(component, :title, fixture.title)
  end

  def template do
    ~HOLO"""
    <p>
      Title: <strong id="title">{@title}</strong>
    </p>
    """
  end
end
