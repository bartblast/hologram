defmodule HologramFeatureTests.ControlFlow.ComprehensionPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/control-flow/comprehension"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="dependent_generator"> Dependent generator </button>
      <button $click="guarding_filter"> Guarding filter </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:dependent_generator, _params, component) do
    result = for x <- [1, 2], y <- [x, x + 10], do: {x, y}

    put_state(component, :result, result)
  end

  def action(:guarding_filter, _params, component) do
    result = for x <- [[1, 2], :nope, [3]], is_list(x), y <- x, do: y

    put_state(component, :result, result)
  end
end
