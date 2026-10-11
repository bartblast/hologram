# The scenario on this page verifies that a module atom in the state brings the struct functions
# of its type to the browser, with no struct of the type anywhere in the payload: init/3 builds the
# module's name from a string, so the compiler sees a string and no module, and the action builds
# the struct from the module it reads from the state. Client-reachable code on this page (template,
# actions) must not name the struct fixture, and neither may any other app code, otherwise the
# scenario silently stops testing that.
defmodule HologramFeatureTests.CallGraph.UnnamedModulePage do
  use Hologram.Page

  route "/call-graph/unnamed-module"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    # The module is loaded by hand, since the BEAM loads a module on first use and nothing has
    # used this one. String.to_atom/1 and not String.to_existing_atom/1 for the same reason: the
    # atom exists only once the module is loaded.
    module = String.to_atom("Elixir.HologramFeatureTests.UnnamedStructFixture")
    Code.ensure_loaded!(module)

    put_state(component, built: nil, type: module)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="build"> Build </button>
    </p>
    <p>
      Built: <strong id="built">{@built}</strong>
    </p>
    """
  end

  def action(:build, _params, component) do
    put_state(component, :built, struct(component.state.type, name: "built from the module"))
  end
end
