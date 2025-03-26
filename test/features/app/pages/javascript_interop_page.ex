defmodule HologramFeatureTests.JavaScriptInteropPage do
  use Hologram.Page

  route "/javascript-interop"

  layout HologramFeatureTests.Components.DefaultLayout

  def template do
    ~HOLO"""
    <p>
      <button $click="run_js_snippet"> Run JavaScript snippet </button>
    </p>
    <p>
      Result: <strong id="result"><code>nil</code></strong>
    </p>
    """
  end

  def action(:run_js_snippet, _params, component) do
    ~JS"""
    document.getElementById('result').querySelector('code').textContent = 'Hologram';
    """

    component
  end
end
