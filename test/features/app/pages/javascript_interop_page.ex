defmodule HologramFeatureTests.JavaScriptInteropPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  alias Hologram.JS

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

    put_state(component, :result, result)
  end

  def action(:run_js_snippet, _params, component) do
    ~JS"""
    document.getElementById('js_snippet_result').querySelector('code').textContent = 'Hologram';
    """

    component
  end
end
