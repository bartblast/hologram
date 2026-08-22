defmodule HologramFeatureTests.Components.CallGraph.JsImportComponent do
  use Hologram.Component
  use Hologram.JS

  js_import :shout, from: "./js_import_component.mjs"

  def init(_props, component, _server) do
    put_state(component, :result, "not called yet")
  end

  def template do
    ~HOLO"""
    <button $click="call_js" id="call_js_button">Call JS</button>
    <p>Result: <strong id="js_call_result">{@result}</strong></p>
    """
  end

  def action(:call_js, _params, component) do
    put_state(component, :result, JS.call(:shout, ["it works"]))
  end
end
