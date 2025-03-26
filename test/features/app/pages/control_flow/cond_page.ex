defmodule HologramFeatureTests.ControlFlow.CondPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  route "/control-flow/cond"

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
      <button $click="basic_case"> Basic case </button>
      <button $click="multiple_expression_clause_condition"> Multiple-expression clause condition </button>
      <button $click={:multiple_clauses, a: false, b: true, c: true}> Multiple clauses </button>
      <button $click={:multiple_expression_clause_body, x: false, y: true, z: true}> Multiple-expression clause body </button>
      <button $click="evaluates_the_first_clause_with_truthy_condition"> Evaluates the first clause with truthy condition </button>
      <button $click="vars_scoping"> Vars scoping </button>
      <button $click={:no_matching_clause, a: false, b: false}> No matching clause </button>
      <button $click="error_in_clause_condition"> Error in clause condition </button>
      <button $click="error_in_clause_body"> Error in clause body </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  # single-expression clause condition / single clause / single-expression clause body
  def action(:basic_case, _params, component) do
    result =
      cond do
        true -> :a
      end

    put_state(component, :result, result)
  end

  def action(:multiple_expression_clause_condition, _params, component) do
    result =
      cond do
        (
          false
          true
        ) ->
          :a
      end

    put_state(component, :result, result)
  end

  def action(:multiple_clauses, params, component) do
    result =
      cond do
        params.a -> :a
        params.b -> :b
        params.c -> :c
      end

    put_state(component, :result, result)
  end

  def action(:multiple_expression_clause_body, params, component) do
    result =
      cond do
        params.x ->
          :x
          :a

        params.y ->
          :y
          :b

        params.z ->
          :z
          :c
      end

    put_state(component, :result, result)
  end

  def action(:evaluates_the_first_clause_with_truthy_condition, _params, component) do
    result =
      cond do
        wrap_term(nil) -> :a
        wrap_term(false) -> :b
        :x -> :c
      end

    put_state(component, :result, result)
  end

  def action(:vars_scoping, _params, component) do
    x = 1
    y = 2
    z = 3

    result =
      cond do
        z = wrap_term(false) ->
          z

        (
          x = 4
          y = 5
        ) ->
          x = x + 10
          {x, y, z}
      end

    put_state(component, :result, {x, y, z, result})
  end

  def action(:no_matching_clause, params, _component) do
    cond do
      params.a -> :a
      params.b -> :b
    end
  end

  def action(:error_in_clause_condition, _params, _component) do
    cond do
      raise(RuntimeError, "my message") -> :a
    end
  end

  def action(:error_in_clause_body, _params, _component) do
    cond do
      true -> raise ArgumentError, "my message"
    end
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end
end
