defmodule HologramFeatureTests.FunctionCalls.FunctionCapturePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.ModuleFixture1

  route "/function-calls/function-capture"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <button $click="single_arg"> Single arg </button>
      <button $click="multiple_args"> Multiple args </button>
      <button $click="local_private_function_capture"> Local private function capture </button>
      <button $click="local_public_function_capture"> Local public function capture </button>
      <button $click="remote_private_elixir_function_capture"> Remote private Elixir function capture </button>
      <button $click="remote_public_elixir_function_capture"> Remote public Elixir function capture </button>
      <button $click="remote_erlang_function_capture"> Remote Erlang function capture </button>
      <button $click="partially_applied_local_function_capture"> Partially applied local function capture </button>
      <button $click="partially_applied_remote_elixir_function_capture"> Partially applied remote Elixir function capture </button>
      <button $click="partially_applied_remote_erlang_function_capture"> Partially applied remote Erlang function capture </button>
      <button $click="vars_scoping"> Vars scoping </button>
      <button $click="closure"> Closure </button>
      <button $click="arity_invalid_called_with_no_args"> Arity invalid, called with no args </button>
      <button $click="arity_invalid_called_with_single_arg"> Arity invalid, called with single arg </button>
      <button $click="arity_invalid_called_with_multple_args"> Arity invalid, called with multiple args </button>
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

  def action(:single_arg, _params, component) do
    fun = & &1
    result = fun.(:a)

    put_state(component, :result, result)
  end

  def action(:multiple_args, _params, component) do
    fun = &{&1, &2}
    result = fun.(:a, :b)

    put_state(component, :result, result)
  end

  def action(:local_private_function_capture, _params, component) do
    fun = &local_private_fun/2
    result = fun.(:a, :b)

    put_state(component, :result, result)
  end

  def action(:local_public_function_capture, _params, component) do
    fun = &local_public_fun/2
    result = fun.(:a, :b)

    put_state(component, :result, result)
  end

  def action(:remote_private_elixir_function_capture, _params, component) do
    module = wrap_term(ModuleFixture1)
    fun = &module.private_fun/2
    result = fun.(:a, :b)

    put_state(component, :result, result)
  end

  def action(:remote_public_elixir_function_capture, _params, component) do
    fun = &ModuleFixture1.public_fun/2
    result = fun.(:a, :b)

    put_state(component, :result, result)
  end

  def action(:remote_erlang_function_capture, _params, component) do
    fun = &:lists.member/2
    result = fun.(:b, [:a, :b])

    put_state(component, :result, result)
  end

  def action(:partially_applied_local_function_capture, _params, component) do
    fun = &local_public_fun(&1, :b)
    result = fun.(:a)

    put_state(component, :result, result)
  end

  def action(:partially_applied_remote_elixir_function_capture, _params, component) do
    fun = &ModuleFixture1.public_fun(&1, :b)
    result = fun.(:a)

    put_state(component, :result, result)
  end

  def action(:partially_applied_remote_erlang_function_capture, _params, component) do
    fun = &:lists.member(&1, [:a, :b])
    result = fun.(:b)

    put_state(component, :result, result)
  end

  def action(:vars_scoping, _params, component) do
    x = 1
    y = 2

    fun =
      &{&1,
       (
         x = 4
         x
       ), y}

    result = fun.(3)

    put_state(component, :result, {x, y, result})
  end

  def action(:closure, _params, component) do
    x = 1
    y = 2

    fun_capture = &{&1, x, y}

    result = local_fun_2(fun_capture)

    put_state(component, :result, result)
  end

  def action(:arity_invalid_called_with_no_args, _params, _component) do
    fun = &{&1, &2}
    fun.()
  end

  def action(:arity_invalid_called_with_single_arg, _params, _component) do
    fun = &{&1, &2}
    fun.(:a)
  end

  def action(:arity_invalid_called_with_multple_args, _params, _component) do
    fun = & &1
    fun.(:a, :b)
  end

  def action(:error_in_body, _params, _component) do
    fun = &{&1, raise(RuntimeError, "my message")}
    fun.(:a)
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end

  def local_public_fun(x, y) do
    {x, y}
  end

  def local_fun_2(fun_capture) do
    x = 3
    y = 4

    {x, y, fun_capture.(5)}
  end

  defp local_private_fun(x, y) do
    {x, y}
  end
end
