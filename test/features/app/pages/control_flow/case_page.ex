defmodule HologramFeatureTests.ControlFlow.CasePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.StructFixture1

  @dialyzer {:no_match, action: 3}

  route "/control-flow/case"

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
      <button $click="multiple_expression_condition"> Multiple-expression condition </button>
      <button $click="multiple_clauses"> Multiple clauses </button>
      <button $click="multiple_expression_clause_body"> Multiple-expression clause body </button>
      <button $click="vars_matching"> Vars matching </button>
      <button $click="vars_scoping"> Vars scoping </button>
      <button $click="var_match_in_condition"> Var match in condition </button>
      <button $click="no_matching_clause"> No matching clause </button>
      <button $click={:error_in_condition, flag: true}> Error in condition </button>
      <button $click="error_in_clause_body"> Error in clause body </button>
    </p>
    <p>
      <button $click="struct_pattern_with_var_field"> Struct pattern with var field </button>
      <button $click="partial_struct_pattern"> Partial struct pattern </button>
      <button $click="bare_struct_pattern"> Bare struct pattern </button>
      <button $click="struct_pattern_with_guard"> Struct pattern with guard </button>
      <button $click="map_vs_struct_pattern"> Map vs struct pattern </button>
      <button $click="no_matching_clause_for_struct"> Unmatched struct pattern </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  # single-expression condition / single clause / single-expression clause body
  def action(:basic_case, _params, component) do
    result =
      case 1 do
        1 -> :a
      end

    put_state(component, :result, result)
  end

  def action(:multiple_expression_condition, _params, component) do
    result =
      case (
             wrap_term(2)
             1
           ) do
        1 -> :a
      end

    put_state(component, :result, result)
  end

  def action(:multiple_clauses, _params, component) do
    result =
      case 2 do
        1 -> :a
        2 -> :b
        3 -> :c
      end

    put_state(component, :result, result)
  end

  def action(:multiple_expression_clause_body, _params, component) do
    result =
      case 2 do
        1 ->
          :x
          :a

        2 ->
          :y
          :b

        3 ->
          :z
          :c
      end

    put_state(component, :result, result)
  end

  def action(:vars_matching, _params, component) do
    result =
      case [2, 3] do
        [4, 5] -> :a
        [x, y] -> {1, x, y}
      end

    put_state(component, :result, result)
  end

  def action(:vars_scoping, _params, component) do
    x = 1
    y = 2

    result =
      case wrap_term(3) do
        x when x > 10 -> :a
        y -> {x, y}
      end

    put_state(component, :result, {x, y, result})
  end

  def action(:var_match_in_condition, _params, component) do
    result =
      case (
             x = 1
             y = 2
             3
           ) do
        x -> {x, y}
      end

    put_state(component, :result, {x, y, result})
  end

  def action(:no_matching_clause, _params, _component) do
    case wrap_term(3) do
      1 -> :a
      2 -> :b
    end
  end

  def action(:error_in_condition, params, _component) do
    case maybe_raise_error(params.flag) do
      x -> x
    end
  end

  def action(:error_in_clause_body, _params, _component) do
    case 1 do
      1 -> raise ArgumentError, "my message"
    end
  end

  # A struct pattern naming only some of the fields, with a var in a field value.
  def action(:struct_pattern_with_var_field, _params, component) do
    result =
      case wrap_term(%StructFixture1{name: "custom", value: 42}) do
        %StructFixture1{value: v} -> v
        _fallback -> :fallback
      end

    put_state(component, :result, result)
  end

  # A partial struct pattern must not constrain the fields it doesn't name.
  def action(:partial_struct_pattern, _params, component) do
    result =
      case wrap_term(%StructFixture1{name: "custom", value: 42}) do
        %StructFixture1{name: "custom"} -> :matched
        _fallback -> :fallback
      end

    put_state(component, :result, result)
  end

  # A bare struct pattern matches the struct whatever its field values are.
  def action(:bare_struct_pattern, _params, component) do
    result =
      case wrap_term(%StructFixture1{name: "custom", value: 42}) do
        %StructFixture1{} -> :matched
        _fallback -> :fallback
      end

    put_state(component, :result, result)
  end

  def action(:struct_pattern_with_guard, _params, component) do
    result =
      case wrap_term(%StructFixture1{name: "custom", value: 42}) do
        %StructFixture1{value: v} when v > 10 -> v
        _fallback -> :fallback
      end

    put_state(component, :result, result)
  end

  # A plain map of the same shape must not match a struct pattern -
  # the __struct__ key is part of the pattern.
  def action(:map_vs_struct_pattern, _params, component) do
    result =
      case wrap_term(%{name: "custom", value: 42}) do
        %StructFixture1{name: "custom"} -> :matched
        _fallback -> :fallback
      end

    put_state(component, :result, result)
  end

  def action(:no_matching_clause_for_struct, _params, _component) do
    case wrap_term(%StructFixture1{name: "other", value: 7}) do
      %StructFixture1{name: "custom"} -> :matched
    end
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end

  defp maybe_raise_error(flag) do
    if flag do
      raise RuntimeError, "my message"
    else
      123
    end
  end
end
