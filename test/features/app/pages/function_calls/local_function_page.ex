defmodule HologramFeatureTests.FunctionCalls.LocalFunctionPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Kernel, except: [inspect: 1]

  route "/function-calls/local-function"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="basic_case"> Basic case </button>
      <button $click="private_function"> Private function </button>
      <button $click="single_arg"> Single arg </button>
      <button $click="multiple_args"> Multiple args </button>
      <button $click="multiple_clauses"> Multiple clauses </button>
      <button $click="multiple_expression_body"> Multiple-expression body </button>
      <button $click="vars_scoping"> Vars scoping </button>
      <button $click="no_matching_clause"> No matching clause </button>
      <button $click="error_in_body"> Error in body </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    <p>
      <button $click="reset"> Reset </button>
    </p>
    """
  end

  # public function / no args / single clause / single-expression body
  def action(:basic_case, _params, component) do
    result = local_fun_1()

    put_state(component, :result, result)
  end

  def action(:private_function, _params, component) do
    result = local_fun_10()

    put_state(component, :result, result)
  end

  def action(:single_arg, _params, component) do
    result = local_fun_2(:a)

    put_state(component, :result, result)
  end

  def action(:multiple_args, _params, component) do
    result = local_fun_3(:a, :b)

    put_state(component, :result, result)
  end

  def action(:multiple_clauses, _params, component) do
    result = local_fun_4(2, :a)

    put_state(component, :result, result)
  end

  def action(:multiple_expression_body, _params, component) do
    result = local_fun_5()

    put_state(component, :result, result)
  end

  def action(:vars_scoping, _params, component) do
    x = 1
    y = 2

    result = local_fun_8(x, 5)

    put_state(component, :result, {x, y, result})
  end

  def action(:no_matching_clause, _params, _component) do
    local_fun_4(4, 5)
  end

  def action(:error_in_body, _params, _component) do
    local_fun_9()
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end

  def local_fun_1 do
    :a
  end

  def local_fun_2(x) do
    x
  end

  def local_fun_3(x, y) do
    {x, y}
  end

  def local_fun_4(1, x) do
    {1, x}
  end

  def local_fun_4(2, x) do
    {2, x}
  end

  def local_fun_4(3, x) do
    {3, x}
  end

  def local_fun_5 do
    :a
    :b
  end

  def local_fun_8(x = 3, y = 4) do
    {x, y}
  end

  def local_fun_8(x, y) do
    x = x + 10
    {x, y}
  end

  def local_fun_9 do
    raise RuntimeError, "my message"
  end

  defp local_fun_10 do
    :a
  end
end
