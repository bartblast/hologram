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
      <button $click="reducer_with_all_rejecting_filter"> Reducer with all-rejecting filter </button>
      <button $click="reducer_with_clause_dispatch"> Reducer with clause dispatch </button>
      <button $click="reducer_with_empty_generator"> Reducer with empty generator </button>
      <button $click="reducer_with_guard_dispatch"> Reducer with guard dispatch </button>
      <button $click="reducer_with_multiple_generators"> Reducer with multiple generators </button>
      <button $click="reducer_with_outer_scope_access"> Reducer with outer scope access </button>
      <button $click="reducer_with_selective_filter"> Reducer with selective filter </button>
      <button $click="reducer_with_single_generator"> Reducer with single generator </button>
      <button $click="reducer_with_unmatched_accumulator"> Reducer with unmatched accumulator </button>
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

  def action(:reducer_with_all_rejecting_filter, _params, component) do
    result =
      for x <- [1, 2], x > 10, reduce: 200 do
        acc -> acc + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_clause_dispatch, _params, component) do
    result =
      for x <- [1, 2, 3], reduce: 0 do
        0 -> x
        acc -> acc * 10 + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_empty_generator, _params, component) do
    result =
      for x <- [], reduce: 100 do
        acc -> acc + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_guard_dispatch, _params, component) do
    result =
      for x <- [1, 2, 3], reduce: 0 do
        acc when acc <= 1 -> acc + x
        acc -> acc + x * 10
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_multiple_generators, _params, component) do
    result =
      for x <- [1, 2], y <- [10, 20], reduce: 0 do
        acc -> acc + x * y
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_outer_scope_access, _params, component) do
    a = 1

    result =
      for x <- [10, 20], reduce: 0 do
        acc -> acc + x + a
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_selective_filter, _params, component) do
    result =
      for x <- [1, 2, 3, 4], rem(x, 2) == 0, reduce: 300 do
        acc -> acc + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_single_generator, _params, component) do
    result =
      for x <- [1, 2, 3], reduce: 0 do
        acc -> acc + x
      end

    put_state(component, :result, result)
  end

  def action(:reducer_with_unmatched_accumulator, _params, _component) do
    for x <- [1], reduce: 0 do
      :nomatch -> x
    end
  end
end
