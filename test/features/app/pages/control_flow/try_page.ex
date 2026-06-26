defmodule HologramFeatureTests.ControlFlow.TryPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  @dialyzer {:no_match, action: 3}

  route "/control-flow/try"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="reset"> Reset </button>
    </p>
    <p>
      <button $click="rescue_unmatched_module"> Rescue unmatched module </button>
      <button $click="rescue_with_multiple_modules"> Rescue with multiple modules </button>
      <button $click="rescue_with_single_module"> Rescue with a single module </button>
      <button $click="rescue_without_module"> Rescue without a module </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:rescue_unmatched_module, _params, _component) do
    try do
      raise RuntimeError, "my message"
    rescue
      e in ArgumentError -> {:rescued_single, e.message}
    end
  end

  def action(:rescue_with_multiple_modules, _params, component) do
    result =
      try do
        raise RuntimeError, "my message"
      rescue
        e in [ArgumentError, RuntimeError] -> {:rescued_multiple, e.message}
      end

    put_state(component, :result, result)
  end

  def action(:rescue_with_single_module, _params, component) do
    result =
      try do
        raise ArgumentError, "my message"
      rescue
        e in ArgumentError -> {:rescued_single, e.message}
      end

    put_state(component, :result, result)
  end

  def action(:rescue_without_module, _params, component) do
    result =
      try do
        raise RuntimeError, "my message"
      rescue
        _exception -> :rescued_any
      end

    put_state(component, :result, result)
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end
end
