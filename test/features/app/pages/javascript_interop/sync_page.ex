defmodule HologramFeatureTests.JavaScriptInterop.SyncPage do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  js_import from: "./calculator.mjs", as: :Calculator
  js_import from: "./helpers.mjs", as: :helpers

  route "/js-interop/sync"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="call_sync_method"> Call sync method</button>
    </p>
    <p>
      <button $click="callback_interop"> Callback interop </button>
    </p>
    <p>
      <button $click="delete_property"> Delete property </button>
    </p>
    <p>
      <button $click="eval_expression"> Evaluate expression </button>
    </p>
    <p>
      <button $click="exec_code"> Execute code </button>
    </p>
    <p>
      <button $click="get_property"> Get property </button>
    </p>
    <p>
      <button $click="instanceof_check"> Instanceof check </button>
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
      <button $click="run_js_sigil_returning_value"> Run JS sigil returning value </button>
    </p>
    <p>
      <button $click="run_js_sigil_void"> Run JS sigil void </button>
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
      JS snippet result: <strong id="js_sigil_result"><code>nil</code></strong>
    </p>
    """
  end

  def action(:call_sync_method, _params, component) do
    result = JS.call(:helpers, :sum, [1, 2])

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:callback_interop, _params, component) do
    result = JS.call(:helpers, :mapArray, [[1, 2, 3], fn x -> x * 2 end])

    put_state(component, :result, result)
  end

  def action(:delete_property, _params, component) do
    calculator = JS.new(:Calculator, [42])
    JS.delete(calculator, :value)

    deleted_value = JS.get(calculator, :value)
    result = JS.typeof(deleted_value)

    put_state(component, :result, {result, is_binary(result)})
  end

  def action(:eval_expression, _params, component) do
    result = JS.eval("3 + 4")

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:exec_code, _params, component) do
    result =
      JS.exec("""
      const x = 2;
      return x + 3;
      """)

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:get_property, _params, component) do
    calculator = JS.new(:Calculator, [10])
    result = JS.get(calculator, :value)

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:instanceof_check, _params, component) do
    calculator = JS.new(:Calculator, [10])
    result = JS.instanceof(calculator, :Calculator)

    put_state(component, :result, {result, is_boolean(result)})
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

  def action(:run_js_sigil_returning_value, _params, component) do
    result = ~JS"""
    const x = 7;
    return x + 4;
    """

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:run_js_sigil_void, _params, component) do
    ~JS"""
    const element = document.getElementById('js_sigil_result').querySelector('code');
    element.textContent = 'Hologram';
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
