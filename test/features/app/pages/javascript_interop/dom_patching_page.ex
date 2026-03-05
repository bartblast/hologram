defmodule HologramFeatureTests.JavaScriptInterop.DOMPatchingPage do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.JS, only: [sigil_JS: 2]
  import Kernel, except: [inspect: 1]

  route "/js-interop/dom-patching"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :counter, 0)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="increment_counter"> Increment counter </button>
    </p>
    <p>
      <button $click="populate_js_subtree"> Populate JS subtree </button>
    </p>
    <p>
      Counter: <strong id="counter"><code>{inspect(@counter)}</code></strong>
    </p>
    <div id="js_managed"></div>
    """
  end

  def action(:increment_counter, _params, component) do
    put_state(component, :counter, component.state.counter + 1)
  end

  def action(:populate_js_subtree, _params, component) do
    ~JS"""
    const container = document.getElementById('js_managed');
    const span = document.createElement('span');
    span.id = 'js_content';
    span.textContent = 'JS managed content';
    container.appendChild(span);
    """

    put_state(component, :counter, component.state.counter + 1)
  end
end
