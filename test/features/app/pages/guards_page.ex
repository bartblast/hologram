defmodule HologramFeatureTests.GuardsPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  route "/guards"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="anonymous_function_single_guard"> Anonymous function - single guard </button>
      <button $click="anonymous_function_multiple_guards"> Anonymous function - multiple guards </button>
    </p>
    <p>
      <button $click="case_expression_single_guard"> Case expression - single guard </button>
      <button $click="case_expression_multiple_guards"> Case expression - multiple guards </button>
    </p>
    <p>
      <button $click="private_function_single_guard"> Private function - single guard </button>
      <button $click="private_function_multiple_guards"> Private function - multiple guards </button>
    </p>    
    <p>
      <button $click="public_function_single_guard"> Public function - single guard </button>
      <button $click="public_function_multiple_guards"> Public function - multiple guards </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="reset"> Reset </button>
    </p>
    """
  end

  def action(:anonymous_function_single_guard, _params, component) do
    fun = fn
      x when x == 1 -> :a
      x when x == 2 -> :b
      x when x == 3 -> :c
    end

    result =
      2
      |> wrap_term()
      |> fun.()

    put_state(component, :result, result)
  end

  def action(:anonymous_function_multiple_guards, _params, component) do
    fun = fn
      x when x > 0 and x < 10 -> :a
      x when x > 10 and x < 20 -> :b
      x when x > 10 and x < 30 -> :c
      x when x > 10 and x < 40 -> :d
    end

    result =
      25
      |> wrap_term()
      |> fun.()

    put_state(component, :result, result)
  end

  def action(:case_expression_single_guard, _params, component) do
    result =
      case wrap_term(2) do
        x when x == 1 -> :a
        x when x == 2 -> :b
        x when x == 3 -> :c
      end

    put_state(component, :result, result)
  end

  def action(:case_expression_multiple_guards, _params, component) do
    result =
      case wrap_term(25) do
        x when x > 0 and x < 10 -> :a
        x when x > 10 and x < 20 -> :b
        x when x > 10 and x < 30 -> :c
        x when x > 10 and x < 40 -> :d
      end

    put_state(component, :result, result)
  end

  def action(:private_function_single_guard, _params, component) do
    result = private_fun_1(2)

    put_state(component, :result, result)
  end

  def action(:private_function_multiple_guards, _params, component) do
    result = private_fun_2(25)

    put_state(component, :result, result)
  end

  def action(:public_function_single_guard, _params, component) do
    result = public_fun_1(2)

    put_state(component, :result, result)
  end

  def action(:public_function_multiple_guards, _params, component) do
    result = public_fun_2(25)

    put_state(component, :result, result)
  end

  def public_fun_1(x) when x == 1 do
    :a
  end

  def public_fun_1(x) when x == 2 do
    :b
  end

  def public_fun_1(x) when x == 3 do
    :c
  end

  def public_fun_2(x) when x > 0 and x < 10 do
    :a
  end

  def public_fun_2(x) when x > 10 and x < 20 do
    :b
  end

  def public_fun_2(x) when x > 10 and x < 30 do
    :c
  end

  def public_fun_2(x) when x > 10 and x < 40 do
    :d
  end

  defp private_fun_1(x) when x == 1 do
    :a
  end

  defp private_fun_1(x) when x == 2 do
    :b
  end

  defp private_fun_1(x) when x == 3 do
    :c
  end

  defp private_fun_2(x) when x > 0 and x < 10 do
    :a
  end

  defp private_fun_2(x) when x > 10 and x < 20 do
    :b
  end

  defp private_fun_2(x) when x > 10 and x < 30 do
    :c
  end

  defp private_fun_2(x) when x > 10 and x < 40 do
    :d
  end
end
