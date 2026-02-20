defmodule HologramFeatureTests.JavaScriptInteropPage do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.JS, only: [js_import: 2, sigil_JS: 2]
  import Kernel, except: [inspect: 1]

  alias Hologram.JS

  js_import "default", from: "./calculator.mjs", as: "Calculator"
  js_import "default", from: "./helpers.mjs", as: "helpers"

  route "/javascript-interop"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="call_global_fun"> Call global fun </button>
    </p>
    <p>
      <button $click="call_imported_fun"> Call imported fun </button>
    </p>
    <p>
      <button $click="new_and_call"> New and call </button>
    </p>
    <p>
      <button $click="run_js_snippet"> Run JavaScript snippet </button>
    </p>
    <p>
      Call result: <strong id="call_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      JS snippet result: <strong id="js_snippet_result"><code>nil</code></strong>
    </p>
    """
  end

  def action(:call_global_fun, _params, component) do
    result = JS.call("Math", "round", [3.7])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:call_imported_fun, _params, component) do
    result = JS.call("helpers", "sum", [1, 2])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:new_and_call, _params, component) do
    calculator = JS.new("Calculator", [10])
    result = JS.call(calculator, "add", [5])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:run_js_snippet, _params, component) do
    ~JS"""
    document.getElementById('js_snippet_result').querySelector('code').textContent = 'Hologram';
    """

    component
  end
end
