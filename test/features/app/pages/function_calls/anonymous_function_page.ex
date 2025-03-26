defmodule HologramFeatureTests.FunctionCalls.AnonymousFunctionPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  route "/function-calls/anonymous-function"

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
      <button $click="single_arg"> Single arg </button>
      <button $click="multiple_args"> Multiple args </button>
      <button $click="multiple_clauses"> Multiple clauses </button>
      <button $click="multiple_expression_body"> Multiple-expression body </button>
      <button $click="vars_scoping"> Vars scoping </button>
      <button $click="closure"> Closure </button>
      <button $click="arity_invalid_called_with_no_args"> Arity invalid, called with no args </button>
      <button $click="arity_invalid_called_with_single_arg"> Arity invalid, called with single arg </button>
      <button $click="arity_invalid_called_with_multple_args"> Arity invalid, called with multiple args </button>
      <button $click="no_matching_clause"> No matching clause </button>
      <button $click="error_in_body"> Error in body </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  # no args / single clause / single-expression body
  def action(:basic_case, _params, component) do
    fun = fn -> :a end
    result = fun.()

    put_state(component, :result, result)
  end

  def action(:single_arg, _params, component) do
    fun = fn x -> x end
    result = fun.(1)

    put_state(component, :result, result)
  end

  def action(:multiple_args, _params, component) do
    fun = fn x, y -> {x, y} end
    result = fun.(1, 2)

    put_state(component, :result, result)
  end

  def action(:multiple_clauses, _params, component) do
    fun = fn
      1, x -> {1, x}
      2, x -> {2, x}
      3, x -> {3, x}
    end

    result =
      2
      |> wrap_term()
      |> fun.(3)

    put_state(component, :result, result)
  end

  def action(:multiple_expression_body, _params, component) do
    fun = fn ->
      :a
      :b
    end

    result = fun.()

    put_state(component, :result, result)
  end

  def action(:vars_scoping, _params, component) do
    x = 1
    y = 2
    z = 3

    fun = fn
      z, y = 4 ->
        {z, y}

      x = 5, y = 6 ->
        x = x + 10
        {x, y, z}
    end

    result = fun.(5, wrap_term(6))

    put_state(component, :result, {x, y, z, result})
  end

  def action(:closure, _params, component) do
    x = 1
    y = 2

    anon_fun = fn -> {x, y} end

    result = local_fun(anon_fun)

    put_state(component, :result, result)
  end

  def action(:arity_invalid_called_with_no_args, _params, _component) do
    fun = fn x, y -> {x, y} end
    fun.()
  end

  def action(:arity_invalid_called_with_single_arg, _params, _component) do
    fun = fn x, y -> {x, y} end
    fun.(:a)
  end

  def action(:arity_invalid_called_with_multple_args, _params, _component) do
    fun = fn x -> x end
    fun.(:a, :b)
  end

  def action(:no_matching_clause, _params, _component) do
    fun = fn
      1, 2 -> :a
      3, 4 -> :b
    end

    5
    |> wrap_term()
    |> fun.(6)
  end

  def action(:error_in_body, _params, _component) do
    fun = fn -> raise RuntimeError, "my message" end
    fun.()
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end

  defp local_fun(anon_fun) do
    x = 3
    y = 4

    {x, y, anon_fun.()}
  end
end
