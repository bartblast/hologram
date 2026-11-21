# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141 do
  # Query builders whose branches and clauses a known argument decides, and builders using
  # constructs the build refuses. The derived fields calling them hand some of them values no
  # clause takes, which is what the walk refuses - those builders pass the values through
  # wrap_term/1, which the build runs for real, so that the compiler doesn't warn about the calls.

  import Hologram.Commons.TestUtils, only: [wrap_term: 1]
  import Hologram.Query

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module55

  def bounded(messages, limit) when limit > 10, do: take(messages, 10)

  def bounded(messages, limit), do: take(messages, ^limit)

  def by_case(messages, kind) do
    case wrap_term(kind) do
      :recent -> take(messages, 2)
      :all -> messages
    end
  end

  def by_kind(messages, kind), do: of_kind(messages, wrap_term(kind))

  def channel_of(messages), do: wrap_term(messages).channel

  def either(messages, kind) when kind == :one or kind == :two, do: take(messages, 1)

  def either(messages, _kind), do: messages

  def first_of({messages, _limit}), do: messages

  def four_ary(messages) do
    pick = fn first, _second, _third, _fourth -> first end

    pick.(messages, 1, 2, 3)
  end

  def invalid(messages), do: filter(messages, nonexistent == 1)

  def limited(messages, opts), do: take(messages, ^wrap_term(opts).limit)

  def listed(messages, ids) when length(ids) > 2, do: take(messages, 2)

  def listed(messages, _ids), do: messages

  def matched(messages) do
    {query, _limit} = {messages, 1}

    query
  end

  def misspelled(messages, opts), do: take(messages, ^wrap_term(opts).lmit)

  def same(messages, value, value), do: take(messages, 1)

  def same(messages, _value, _other), do: take(messages, 2)

  def sized(messages, size) do
    cond do
      size > 10 -> take(messages, 10)
      size > 0 -> take(messages, ^size)
      true -> messages
    end
  end

  def strict_or_all(messages, strict) do
    if strict do
      take(messages, 1)
    else
      messages
    end
  end

  def strictly_sized(messages, size) do
    cond do
      size > 10 -> take(messages, 10)
      size > 0 -> take(messages, ^size)
    end
  end

  def tagged(messages, kind) do
    case {kind, 1} do
      {:recent, _limit} -> take(messages, 2)
      _other -> messages
    end
  end

  def undefined(messages), do: wrap_term(Module55).missing_helper(messages)

  def wildcard_bound(messages) do
    # credo:disable-for-next-line Credo.Check.Consistency.UnusedVariableNames
    _ = take(messages, 1)

    count(messages)
  end

  def wildcard_invalid(messages) do
    # credo:disable-for-next-line Credo.Check.Consistency.UnusedVariableNames
    _ = filter(messages, nonexistent == 1)

    messages
  end

  def undefined_native(messages) do
    _missing = wrap_term(String).not_a_function(1)

    messages
  end

  def undefined_inside_native(messages) do
    # credo:disable-for-next-line Credo.Check.Refactor.Apply
    _missing = apply(wrap_term(String), :not_a_function, [1])

    messages
  end

  def not_a_module_target(messages) do
    _missing = wrap_term("x").not_a_function(1)

    messages
  end

  def windowed(messages, from, to) when from >= 0 and to > from, do: take(messages, ^to)

  def windowed(messages, _from, _to), do: messages

  defp of_kind(messages, :recent), do: take(messages, 2)

  defp of_kind(messages, :all), do: messages
end
