# The scenario on this page verifies that a struct whose type no app code names reaches the browser
# with its protocol implementations: init/3 builds the module's name from a string, so the
# compiler sees a string and no module. Client-reachable code on this page (template, actions)
# must not name the struct fixture, and neither may any other app code, otherwise the scenario
# silently stops testing that.
defmodule HologramFeatureTests.CallGraph.UnnamedStructPage do
  use Hologram.Page

  route "/call-graph/unnamed-struct"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    # The module is loaded by hand, since the BEAM loads a module on first use and nothing has
    # used this one. String.to_atom/1 and not String.to_existing_atom/1 for the same reason: the
    # atom exists only once the module is loaded.
    module = String.to_atom("Elixir.HologramFeatureTests.UnnamedStructFixture")
    Code.ensure_loaded!(module)

    put_state(component,
      label: "initial",
      unnamed: struct(module, name: "created from a string")
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
      Unnamed: <strong id="unnamed">{@unnamed}</strong>
    </p>
    """
  end

  def action(:relabel, _params, component) do
    put_state(component, :label, "relabeled")
  end
end
