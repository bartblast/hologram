defmodule HologramFeatureTests.StacktracePage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  alias HologramFeatureTests.StacktraceFixture

  # The anonymous function the first scenario raises in never returns, and an
  # anonymous function can't be annotated by name - so the warning is silenced on
  # the clause holding it. Every action/3 clause here does return.
  @dialyzer {:nowarn_function, action: 3}

  # StacktraceFixture.raise_error/1 always raises, so local_fun/1 never returns.
  @dialyzer {:no_return, local_fun: 1}

  route "/stacktrace"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <strong>Controls</strong>
      <button $click="reset"> Reset </button>
    </p>
    <p>
      <strong>Scenarios</strong>
      <button $click="anonymous_function"> Anonymous function </button>
      <button $click="nested_calls"> Nested calls </button>
      <button $click="no_matching_clause"> No matching clause </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  # The stacktrace tests pin the lines the frames below point at, so edits that
  # move this module's definitions around must be reflected there.
  # Every call in the chains is deliberately non-tail (its result lands in a
  # tuple), because the BEAM's last-call optimization would otherwise drop the
  # caller's frame from the trace.

  def action(:anonymous_function, _params, component) do
    fun = fn x ->
      {x, raise("raised in an anonymous function")}
    end

    result =
      try do
        {:wrapped, fun.(1)}
      rescue
        _exception -> {:anonymous_function_trace, __STACKTRACE__}
      end

    put_state(component, :result, result)
  end

  def action(:nested_calls, _params, component) do
    result =
      try do
        {:wrapped, local_fun(1)}
      rescue
        _exception -> {:nested_calls_trace, __STACKTRACE__}
      end

    put_state(component, :result, result)
  end

  def action(:no_matching_clause, _params, component) do
    result =
      try do
        # The argument is wrapped so the clause it doesn't match is found at
        # runtime, which is where a stacktrace is taken.
        {:wrapped, only_tuple(wrap_term(:not_a_tuple))}
      rescue
        _exception -> {:no_matching_clause_trace, __STACKTRACE__}
      end

    put_state(component, :result, result)
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end

  defp local_fun(x) do
    {
      x,
      StacktraceFixture.raise_error(x)
    }
  end

  defp only_tuple({_first, _second}), do: :ok
end
