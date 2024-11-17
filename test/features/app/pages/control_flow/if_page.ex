defmodule HologramFeatureTests.ControlFlow.IfPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/control-flow/if"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~H"""
    <p>
      <button $click="reset"> Reset </button>
    </p>
    <p>
      <button $click="basic_case"> Basic case </button>
      <button $click="multiple_expression_condition"> Multiple-expression condition </button>
      <button $click="multiple_expression_if_body"> Multiple-expression if body </button>
      <button $click="unmet_condition_no_else_body"> Unmet condition, no else body </button>
      <button $click="single_expression_else_body"> Single-expression else body </button>
      <button $click="multiple_expression_else_body"> Multiple-expression else body </button>
      <button $click="vars_scoping_in_if_body"> Vars scoping in if body </button>
      <button $click="vars_scoping_in_else_body"> Vars scoping in else body </button>
      <button $click="error_in_condition"> Error in condition </button>
      <button $click="error_in_if_body"> Error in if body </button>
      <button $click="error_in_else_body"> Error in else body </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  # single-expression condition / single-expression if body / no else expression
  def action(:basic_case, _params, component) do
    result =
      if true do
        :a
      end

    put_state(component, :result, result)
  end

  def action(:multiple_expression_condition, _params, component) do
    result =
      if (
           false
           true
         ) do
        :a
      end

    put_state(component, :result, result)
  end

  def action(:multiple_expression_if_body, _params, component) do
    result =
      if true do
        :x
        :a
      end

    put_state(component, :result, result)
  end

  def action(:unmet_condition_no_else_body, _params, component) do
    result =
      if false do
        :a
      end

    put_state(component, :result, result)
  end

  def action(:single_expression_else_body, _params, component) do
    result =
      if false do
        :a
      else
        :b
      end

    put_state(component, :result, result)
  end

  def action(:multiple_expression_else_body, _params, component) do
    result =
      if false do
        :a
      else
        :b
        :c
      end

    put_state(component, :result, result)
  end

  def action(:vars_scoping_in_if_body, _params, component) do
    z = 3

    result =
      if (
           x = 1
           y = 2
         ) do
        x = x + 10
        {x, y, z}
      end

    put_state(component, :result, {x, y, z, result})
  end

  def action(:vars_scoping_in_else_body, _params, component) do
    z = 3

    result =
      if (
           x = 1
           y = 2
           false
         ) do
        :a
      else
        x = x + 10
        {x, y, z}
      end

    put_state(component, :result, {x, y, z, result})
  end

  def action(:error_in_condition, _params, _component) do
    if (
         message = "my message"
         raise RuntimeError, message
       ) do
      :a
    end
  end

  def action(:error_in_if_body, _params, _component) do
    if true do
      raise ArgumentError, "my message"
    end
  end

  def action(:error_in_else_body, _params, _component) do
    if false do
      :a
    else
      raise ArgumentError, "my message"
    end
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end
end
