# The component rendered here declares a js_import and is referenced in broadcast caller code,
# which puts its client code into the runtime bundle. That bundle is then the only one that can
# register the component's JS bindings, since the page bundles no longer carry its MFAs.
defmodule HologramFeatureTests.CallGraph.JsImportsPage do
  use Hologram.Page

  alias HologramFeatureTests.Components.CallGraph.JsImportComponent

  route "/call-graph/js-imports"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <JsImportComponent cid="js_import_component" />
    <p>Suffix: <strong id="suffix">{JsImportComponent.suffix()}</strong></p>
    """
  end

  # The test never sends this broadcast - referencing the component here is what moves it into
  # the runtime bundle.
  def command(:broadcast_component, _params, server) do
    put_broadcast(server, :call_graph_js_imports, :put_module, module: JsImportComponent)
  end
end
