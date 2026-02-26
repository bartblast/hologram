defmodule HologramFeatureTests.JavaScriptInteropPage do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.JS, only: [js_import: 2, sigil_JS: 2]
  import Kernel, except: [inspect: 1]

  alias Hologram.JS

  js_import :default, from: "./calculator.mjs", as: :Calculator
  js_import :default, from: "./helpers.mjs", as: :helpers

  route "/js-interop"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="async_cond"> Async cond </button>
    </p>
    <p>
      <button $click="call_async_method"> Call async method </button>
    </p>
    <p>
      <button $click="call_promise_method"> Call promise method </button>
    </p>
    <p>
      <button $click="call_sync_method"> Call sync method</button>
    </p>
    <p>
      <button $click="get_property"> Get property </button>
    </p>
    <p>
      <button $click="new_instance"> New instance </button>
    </p>
    <p>
      <button $click="resolve_global"> Resolve global </button>
    </p>
    <p>
      <button $click="resolve_imported"> Resolve imported </button>
    </p>
    <p>
      <button $click="resolve_object_ref"> Resolve object ref </button>
    </p>
    <p>
      <button $click="run_js_snippet"> Run JavaScript snippet </button>
    </p>
    <p>
      <button $click="set_property"> Set property </button>
    </p>
    <p>
      <button $click="typeof_value"> Typeof value </button>
    </p>
    <p>
      Call result: <strong id="call_result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      JS snippet result: <strong id="js_snippet_result"><code>nil</code></strong>
    </p>
    """
  end

  def action(:async_cond, _params, component) do
    result = JS.call_async(:helpers, :asyncSum, [15, 25])

    label =
      cond do
        result == 41 -> :wrong
        result == 40 -> :correct
        true -> :unknown
      end

    put_state(component, :result, label)
  end

  def action(:call_async_method, _params, component) do
    result = JS.call_async(:helpers, :asyncSum, [10, 20])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:call_promise_method, _params, component) do
    result = JS.call_async(:helpers, :promiseSum, [100, 200])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:call_sync_method, _params, component) do
    result = JS.call(:helpers, :sum, [1, 2])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:get_property, _params, component) do
    calculator = JS.new(:Calculator, [10])
    result = JS.get(calculator, :value)

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:new_instance, _params, component) do
    calculator = JS.new(:Calculator, [42])
    result = JS.get(calculator, :value)

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:resolve_global, _params, component) do
    result = JS.call(:Math, :round, [3.7])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:resolve_imported, _params, component) do
    result = JS.call(:helpers, :sum, [5, 7])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:resolve_object_ref, _params, component) do
    calculator = JS.new(:Calculator, [10])
    result = JS.call(calculator, :add, [5])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:run_js_snippet, _params, component) do
    ~JS"""
    document.getElementById('js_snippet_result').querySelector('code').textContent = 'Hologram';
    """

    component
  end

  def action(:set_property, _params, component) do
    calculator = JS.new(:Calculator, [10])
    JS.set(calculator, :value, 20)
    result = JS.get(calculator, :value)

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:typeof_value, _params, component) do
    calculator = JS.new(:Calculator, [10])
    result = JS.typeof(calculator)

    put_state(component, :result, result)
  end
end
