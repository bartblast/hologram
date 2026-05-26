defmodule HologramFeatureTests.ControlFlow.WithPage do
  use Hologram.Page

  import Hologram.Commons.KernelUtils, only: [inspect: 1]
  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Kernel, except: [inspect: 1]

  # Several actions deliberately use with clauses that can never match (to exercise the
  # else, error, and unmatched-value paths), which Dialyzer would otherwise flag.
  @dialyzer {:no_match, action: 3}

  # credo:disable-for-this-file Credo.Check.Readability.WithSingleClause
  # credo:disable-for-this-file Credo.Check.Refactor.WithClauses

  # Some actions below wrap their value in wrap_term/1 to keep it opaque to the compiler.
  # Without it, some Elixir versions emit "this check/guard will always yield the same
  # result" for a literal `<-` / `=` clause that can never match, or for an always-false
  # guard.

  route "/control-flow/with"

  layout HologramFeatureTests.Components.DefaultLayout

  def init(_params, component, _server) do
    put_state(component, :result, nil)
  end

  def template do
    ~HOLO"""
    <p>
      <strong>Controls</strong>
      <button $click="auxiliary"> Auxiliary </button>
      <button $click="reset"> Reset </button>
    </p>
    <p>
      <strong>No clauses / no else clauses</strong>
      <button $click="empty_with"> Empty with </button>
      <button $click="no_else_passthrough"> No else clauses passthrough </button>
    </p>
    <p>
      <strong>Match clauses</strong>
      <button $click="single_matching_clause"> Single matching clause </button>
      <button $click="multiple_matching_clauses"> Multiple matching clauses </button>
      <button $click="clause_with_passing_guard"> Clause with passing guard </button>
    </p>
    <p>
      <strong>Bare clauses</strong>
      <button $click="bare_clause_that_binds"> Bare clause that binds </button>
      <button $click="bare_clause_that_does_not_bind"> Bare clause that does not bind </button>
      <button $click="multiple_bare_clauses"> Multiple bare clauses </button>
      <button $click="bare_clause_match_error"> Bare clause MatchError </button>
    </p>
    <p>
      <strong>Else clauses</strong>
      <button $click="failed_match_to_single_else"> Failed match to single else </button>
      <button $click="matching_clause_among_multiple_else"> Matching clause among multiple else </button>
      <button $click="guarded_else_clause"> Guarded else clause </button>
      <button $click="failed_guard_to_else"> Failed guard to else </button>
      <button $click="no_matching_else_clause"> No matching else clause </button>
    </p>
    <p>
      <strong>Variable scoping</strong>
      <button $click="does_not_leak"> Does not leak </button>
      <button $click="else_in_original_context"> Else in original context </button>
      <button $click="later_clause_shadows"> Later clause shadows </button>
    </p>
    <p>
      Result: <strong id="result"><code>{inspect(@result)}</code></strong>
    </p>
    """
  end

  def action(:auxiliary, _params, component) do
    put_state(component, :result, :auxiliary)
  end

  def action(:bare_clause_match_error, _params, _component) do
    a = wrap_term(:ok)

    with :error = a do
      :body
    end
  end

  def action(:bare_clause_that_binds, _params, component) do
    a = :ok

    result =
      with b = a do
        {a, b}
      end

    put_state(component, :result, result)
  end

  def action(:bare_clause_that_does_not_bind, _params, component) do
    a = :ok

    result =
      with b <- a,
           :noop do
        {a, b}
      end

    put_state(component, :result, result)
  end

  def action(:clause_with_passing_guard, _params, component) do
    a = :ok

    result =
      with b when b == :ok <- a do
        {a, b}
      end

    put_state(component, :result, result)
  end

  def action(:does_not_leak, _params, component) do
    a = :ok

    with b <- a do
      a = 2
      {a, b}
    end

    put_state(component, :result, a)
  end

  def action(:else_in_original_context, _params, component) do
    x = :original
    a = :ok

    result =
      with x <- a,
           :fail <- wrap_term(:mismatch) do
        x
      else
        _fallback -> x
      end

    put_state(component, :result, result)
  end

  def action(:empty_with, _params, component) do
    result = with do: nil

    put_state(component, :result, result)
  end

  def action(:failed_guard_to_else, _params, component) do
    a = wrap_term(:ok)

    result =
      with b when b == :no <- a do
        :body
      else
        :ok -> {:error, :nomatch}
      end

    put_state(component, :result, result)
  end

  def action(:failed_match_to_single_else, _params, component) do
    a = wrap_term(:ok)

    result =
      with :error <- a do
        :body
      else
        :ok -> :match
      end

    put_state(component, :result, result)
  end

  def action(:guarded_else_clause, _params, component) do
    a = wrap_term(:ok)

    result =
      with :error <- a do
        :body
      else
        e when e == :ok -> {:guarded, e}
      end

    put_state(component, :result, result)
  end

  def action(:later_clause_shadows, _params, component) do
    result =
      with a <-
             (
               b = 1
               _var = b
               1
             ),
           b <- 2 do
        a + b
      end

    put_state(component, :result, result)
  end

  def action(:matching_clause_among_multiple_else, _params, component) do
    a = wrap_term(:ok)

    result =
      with :error <- a do
        :body
      else
        :a -> :first
        :ok -> :second
        :c -> :third
      end

    put_state(component, :result, result)
  end

  def action(:multiple_bare_clauses, _params, component) do
    a = :ok

    result =
      with b = a,
           c = b do
        {a, b, c}
      end

    put_state(component, :result, result)
  end

  def action(:multiple_matching_clauses, _params, component) do
    a = :ok

    result =
      with b <- a,
           :ok <- b do
        {a, b}
      end

    put_state(component, :result, result)
  end

  def action(:no_else_passthrough, _params, component) do
    a = wrap_term(:ok)

    result =
      with :error <- a do
        :body
      end

    put_state(component, :result, result)
  end

  def action(:no_matching_else_clause, _params, _component) do
    a = wrap_term(:ok)

    with :error <- a do
      :body
    else
      :other -> nil
    end
  end

  def action(:reset, _params, component) do
    put_state(component, :result, nil)
  end

  def action(:single_matching_clause, _params, component) do
    a = :ok

    result =
      with b <- a do
        {a, b}
      end

    put_state(component, :result, result)
  end
end
