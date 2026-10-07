# The scenario on this page verifies that a module atom a command sends in an action's params
# brings the struct functions of its type to the browser: the command builds the module's name
# from a string, so the compiler sees a string and no module, and the action builds the struct
# from the module it is given. Client-reachable code on this page (template, actions) must not
# name the struct fixture, and neither may any other app code, otherwise the scenario silently
# stops testing that. The page's document must name no chunk of the fixture's type either.
defmodule HologramFeatureTests.CallGraph.PushedModulePage do
  use Hologram.Page

  route "/call-graph/pushed-module"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :built, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="load"> Load </button>
    </p>
    <p>
      Built: <strong id="built">{@built}</strong>
    </p>
    """
  end

  def action(:build, params, component) do
    put_state(component, :built, struct(params.type, name: "built from a pushed module"))
  end

  def action(:load, _params, component) do
    put_command(component, :load)
  end

  def command(:load, _params, server) do
    # See UnnamedModulePage.init/3 for the loading and the atom.
    module = String.to_atom("Elixir.HologramFeatureTests.UnnamedStructFixture")
    Code.ensure_loaded!(module)

    put_action(server, :build, type: module)
  end
end
