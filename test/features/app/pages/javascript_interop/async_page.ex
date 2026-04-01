defmodule HologramFeatureTests.JavaScriptInterop.AsyncPage do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  js_import from: "./helpers.mjs", as: :helpers
  js_import :AsyncCounter, from: "./helpers.mjs"
  js_import :promiseValue, from: "./helpers.mjs"

  route "/js-interop/async"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="async_anonymous_function_call"> Async anonymous function call </button>
    </p>
    <p>
      <button $click="async_apply"> Async apply </button>
    </p>
    <p>
      <button $click="async_case"> Async case </button>
    </p>
    <p>
      <button $click="async_comprehension"> Async comprehension </button>
    </p>
    <p>
      <button $click="async_cond"> Async cond </button>
    </p>
    <p>
      <button $click="async_dynamic_call"> Async dynamic call </button>
    </p>
    <p>
      <button $click="async_eval"> Async eval </button>
    </p>
    <p>
      <button $click="async_exec"> Async exec </button>
    </p>
    <p>
      <button $click="async_get"> Async get </button>
    </p>
    <p>
      <button $click="async_new"> Async new </button>
    </p>
    <p>
      <button $click="call_async_method"> Call async method </button>
    </p>
    <p>
      <button $click="call_promise_method"> Call promise method </button>
    </p>
    <p>
      Call result: <strong id="call_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:async_anonymous_function_call, _params, component) do
    fun = fn x, y ->
      :helpers
      |> JS.call(:asyncSum, [x, y])
      |> Task.await()
    end

    result = fun.(13, 14)

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:async_apply, _params, component) do
    result =
      :helpers
      |> JS.call(:asyncSum, [15, 16])
      |> Task.await()

    is_int = apply(Kernel, :is_integer, [result])

    put_state(component, :result, {result, is_int})
  end

  def action(:async_case, _params, component) do
    result =
      :helpers
      |> JS.call(:asyncSum, [12, 23])
      |> Task.await()

    label =
      case result do
        36 -> :wrong
        35 -> :matched
        _fallback -> :unknown
      end

    put_state(component, :result, label)
  end

  def action(:async_comprehension, _params, component) do
    multiplier =
      :helpers
      |> JS.call(:asyncSum, [1, 2])
      |> Task.await()

    result = for x <- [10, 20, 30], do: x * multiplier

    put_state(component, :result, result)
  end

  def action(:async_cond, _params, component) do
    result =
      :helpers
      |> JS.call(:asyncSum, [15, 25])
      |> Task.await()

    label =
      cond do
        result == 41 -> :wrong
        result == 40 -> :correct
        true -> :unknown
      end

    put_state(component, :result, label)
  end

  def action(:async_dynamic_call, _params, component) do
    result =
      :helpers
      |> JS.call(:asyncSum, [17, 16])
      |> Task.await()

    module = HologramFeatureTests.ModuleFixture3
    is_int = module.is_integer(result)

    put_state(component, :result, {result, is_int})
  end

  def action(:async_eval, _params, component) do
    result =
      "new Promise(resolve => setTimeout(() => resolve(88), 50))"
      |> JS.eval()
      |> Task.await()

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:async_exec, _params, component) do
    result =
      "return new Promise(resolve => setTimeout(() => resolve(66), 50))"
      |> JS.exec()
      |> Task.await()

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:async_get, _params, component) do
    result =
      :promiseValue
      |> JS.get(:data)
      |> Task.await()

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:async_new, _params, component) do
    obj =
      :AsyncCounter
      |> JS.new([50])
      |> Task.await()

    result = JS.get(obj, :value)

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:call_async_method, _params, component) do
    result =
      :helpers
      |> JS.call(:asyncSum, [10, 20])
      |> Task.await()

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:call_promise_method, _params, component) do
    result =
      :helpers
      |> JS.call(:promiseSum, [100, 200])
      |> Task.await()

    put_state(component, :result, {result, is_integer(result)})
  end
end
