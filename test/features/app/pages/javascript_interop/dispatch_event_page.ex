defmodule HologramFeatureTests.JavaScriptInterop.DispatchEventPage do
  use Hologram.Page
  use Hologram.JS

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/js-interop/dispatch-event"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <div id="dispatch_target"></div>
    <p>
      <button $click="dispatch_cancelable"> Dispatch cancelable </button>
    </p>
    <p>
      <button $click="dispatch_default"> Dispatch default </button>
    </p>
    <p>
      <button $click="dispatch_on_document"> Dispatch on document </button>
    </p>
    <p>
      <button $click="dispatch_with_detail"> Dispatch with detail </button>
    </p>
    <p>
      <button $click="dispatch_with_event_type"> Dispatch with event type </button>
    </p>
    <p>
      Call result: <strong id="call_result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:dispatch_cancelable, _params, component) do
    target = JS.call(:document, :getElementById, ["dispatch_target"])

    JS.call(target, :addEventListener, [
      "test:gamma",
      fn event ->
        JS.call(event, :preventDefault, [])
      end
    ])

    result = JS.dispatch_event(target, :CustomEvent, "test:gamma", cancelable: true)

    put_state(component, :result, {result, is_boolean(result)})
  end

  def action(:dispatch_default, _params, component) do
    target = JS.call(:document, :getElementById, ["dispatch_target"])

    JS.call(target, :addEventListener, [
      "test:alpha",
      fn event ->
        JS.set(:window, :__captured__, JS.get(event, :type))
      end
    ])

    JS.dispatch_event(target, "test:alpha")

    result = JS.get(:window, :__captured__)

    put_state(component, :result, result)
  end

  def action(:dispatch_on_document, _params, component) do
    JS.call(:document, :addEventListener, [
      "test:delta",
      fn event ->
        JS.set(:window, :__captured__, JS.get(event, :type))
      end
    ])

    JS.dispatch_event(:document, "test:delta")

    result = JS.get(:window, :__captured__)

    put_state(component, :result, result)
  end

  def action(:dispatch_with_detail, _params, component) do
    target = JS.call(:document, :getElementById, ["dispatch_target"])

    JS.call(target, :addEventListener, [
      "test:beta",
      fn event ->
        detail = JS.get(event, :detail)
        JS.set(:window, :__captured__, JS.get(detail, :value))
      end
    ])

    JS.dispatch_event(target, "test:beta", detail: %{value: 99})

    result = JS.get(:window, :__captured__)

    put_state(component, :result, {result, is_integer(result)})
  end

  def action(:dispatch_with_event_type, _params, component) do
    target = JS.call(:document, :getElementById, ["dispatch_target"])

    JS.call(target, :addEventListener, [
      "click",
      fn event ->
        constructor = JS.get(event, :constructor)
        JS.set(:window, :__captured__, JS.get(constructor, :name))
      end
    ])

    JS.dispatch_event(target, :MouseEvent, "click")

    result = JS.get(:window, :__captured__)

    put_state(component, :result, result)
  end
end
