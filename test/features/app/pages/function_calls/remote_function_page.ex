defmodule HologramFeatureTests.FunctionCalls.RemoteFunctionPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.ModuleFixture2

  route "/function-calls/remote-function"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="basic_case"> Basic case </button>
      <button $click="private_function"> Private function </button>
      <button $click="erlang_function"> Erlang function </button>
      <button $click="single_arg"> Single arg </button>
      <button $click="multiple_args"> Multiple args </button>
      <button $click="multiple_clauses"> Multiple clauses </button>
      <button $click="multiple_expression_body"> Multiple-expression body </button>
      <button $click="vars_scoping"> Vars scoping </button>
      <button $click="arity_invalid_called_with_no_args"> Arity invalid, called with no args </button>
      <button $click="arity_invalid_called_with_single_arg"> Arity invalid, called with single arg </button>
      <button $click="arity_invalid_called_with_multple_args"> Arity invalid, called with multiple args </button>
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

  # public function / Elixir function / no args / single clause / single-expression body
  def action(:basic_case, _params, component) do
    result = ModuleFixture2.fun_1()

    put_state(component, :result, result)
  end

  def action(:private_function, _params, _component) do
    wrap_term(ModuleFixture2).fun_2()
  end

  def action(:erlang_function, _params, component) do
    result = :erlang.hd([1, 2, 3])

    put_state(component, :result, result)
  end

  def action(:single_arg, _params, component) do
    result = ModuleFixture2.fun_3(:a)

    put_state(component, :result, result)
  end

  def action(:multiple_args, _params, component) do
    result = ModuleFixture2.fun_4(:a, :b)

    put_state(component, :result, result)
  end

  def action(:multiple_clauses, _params, component) do
    result = ModuleFixture2.fun_5(2, :a)

    put_state(component, :result, result)
  end

  def action(:multiple_expression_body, _params, component) do
    result = ModuleFixture2.fun_6()

    put_state(component, :result, result)
  end

  def action(:vars_scoping, _params, component) do
    x = 1
    y = 2

    result = ModuleFixture2.fun_9(x, 5)

    put_state(component, :result, {x, y, result})
  end

  def action(:arity_invalid_called_with_no_args, _params, _component) do
    wrap_term(ModuleFixture2).fun_4()
  end

  def action(:arity_invalid_called_with_single_arg, _params, _component) do
    wrap_term(ModuleFixture2).fun_4(:a)
  end

  def action(:arity_invalid_called_with_multple_args, _params, _component) do
    wrap_term(ModuleFixture2).fun_3(:a, :b)
  end

  def action(:no_matching_clause, _params, _component) do
    ModuleFixture2.fun_5(4, 5)
  end

  def action(:error_in_body, _params, _component) do
    ModuleFixture2.fun_10()
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end
end
