# The scenarios on this page verify that protocol implementations ship for types
# referenced only in server-executed code (init/3, command/3). Client-reachable
# code on this page (template, actions) must not reference the struct fixtures,
# otherwise the scenarios silently stop testing the server-side type harvest.
defmodule HologramFeatureTests.CallGraph.ServerCreatedStructsPage do
  use Hologram.Page

  alias HologramFeatureTests.StructFixture3

  route "/call-graph/server-created-structs"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component,
      label: "initial",
      struct_from_init: %StructFixture3{name: "created in init"}
    )
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="relabel"> Relabel </button>
    </p>
    <p>
      Label: <strong id="label">{@label}</strong>
    </p>
    <p>
      Result: <strong id="result">{@struct_from_init}</strong>
    </p>
    """
  end

  def action(:relabel, _params, component) do
    put_state(component, :label, "relabeled")
  end
end
