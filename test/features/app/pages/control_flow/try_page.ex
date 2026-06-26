defmodule HologramFeatureTests.ControlFlow.TryPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  @dialyzer {:no_match, action: 3}

  route "/control-flow/try"

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
      <strong>Rescue clauses</strong>
      <button $click="rescue_without_module"> Rescue without a module </button>
      <button $click="rescue_with_single_module"> Rescue with a single module </button>
      <button $click="rescue_with_multiple_modules"> Rescue with multiple modules </button>
      <button $click="rescue_unmatched_module"> Rescue unmatched module </button>
    </p>
    <p>
      <strong>Catch clauses</strong>
      <button $click="catch_throw"> Catch throw </button>
      <button $click="catch_exit"> Catch exit </button>
      <button $click="catch_error"> Catch error </button>
      <button $click="catch_unmatched_kind"> Catch unmatched kind </button>
    </p>
    <p>
      <strong>Else clauses</strong>
      <button $click="else_with_match"> Else with a match </button>
      <button $click="else_without_match"> Else without a match </button>
    </p>
    <p>
      <strong>After block</strong>
      <button $click="after_keeps_result"> After keeps result </button>
      <button $click="after_runs_on_success"> After runs on success </button>
      <button $click="after_runs_on_failure"> After runs on failure </button>
    </p>
    <p>
      <strong>Variable scoping</strong>
      <button $click="do_vars_do_not_leak"> Do block vars do not leak </button>
      <button $click="clause_vars_do_not_leak"> Clause vars do not leak </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:after_keeps_result, _params, component) do
    result =
      try do
        :body_result
      after
        :ignored
      end

    put_state(component, :result, result)
  end

  def action(:after_runs_on_failure, _params, _component) do
    try do
      raise ArgumentError, "boom"
    after
      raise RuntimeError, "after ran"
    end
  end

  def action(:after_runs_on_success, _params, _component) do
    try do
      :ok
    after
      raise RuntimeError, "after ran"
    end
  end

  def action(:catch_error, _params, component) do
    result =
      try do
        raise RuntimeError, "my message"
      catch
        :error, reason -> {:caught_error, reason.message}
      end

    put_state(component, :result, result)
  end

  def action(:catch_exit, _params, component) do
    result =
      try do
        exit("my reason")
      catch
        :exit, reason -> {:caught_exit, reason}
      end

    put_state(component, :result, result)
  end

  def action(:catch_throw, _params, component) do
    result =
      try do
        throw("my value")
      catch
        value -> {:caught_throw, value}
      end

    put_state(component, :result, result)
  end

  def action(:catch_unmatched_kind, _params, _component) do
    try do
      raise RuntimeError, "my message"
    catch
      :throw, value -> {:caught_throw, value}
    end
  end

  def action(:clause_vars_do_not_leak, _params, component) do
    x = wrap_term(1)

    result =
      try do
        raise RuntimeError, "boom"
      rescue
        _exception ->
          x = 2
          x
      end

    put_state(component, :result, {x, result})
  end

  def action(:do_vars_do_not_leak, _params, component) do
    x = wrap_term(1)

    result =
      try do
        x = 2
        x
      after
        nil
      end

    put_state(component, :result, {x, result})
  end

  def action(:else_with_match, _params, component) do
    value = wrap_term(2)

    result =
      try do
        value
      else
        1 -> :else_one
        2 -> :else_two
      after
        nil
      end

    put_state(component, :result, result)
  end

  def action(:else_without_match, _params, _component) do
    value = wrap_term(:no_match)

    try do
      value
    else
      :other -> nil
    after
      nil
    end
  end

  def action(:rescue_unmatched_module, _params, _component) do
    try do
      raise RuntimeError, "my message"
    rescue
      e in ArgumentError -> {:rescued_single, e.message}
    end
  end

  def action(:rescue_with_multiple_modules, _params, component) do
    result =
      try do
        raise RuntimeError, "my message"
      rescue
        e in [ArgumentError, RuntimeError] -> {:rescued_multiple, e.message}
      end

    put_state(component, :result, result)
  end

  def action(:rescue_with_single_module, _params, component) do
    result =
      try do
        raise ArgumentError, "my message"
      rescue
        e in ArgumentError -> {:rescued_single, e.message}
      end

    put_state(component, :result, result)
  end

  def action(:rescue_without_module, _params, component) do
    result =
      try do
        raise RuntimeError, "my message"
      rescue
        _exception -> :rescued_any
      end

    put_state(component, :result, result)
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end
end
