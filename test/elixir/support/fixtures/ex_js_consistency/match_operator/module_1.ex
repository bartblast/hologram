# credo:disable-for-this-file /Credo.Check.Consistency.ParameterPatternMatching|Credo.Check.Readability.Specs/
defmodule Hologram.Test.Fixtures.ExJsConsistency.MatchOperator.Module1 do
  def test_a(a = 1), do: %{a: a}

  def test_b(1 = a), do: %{a: a}

  def test_c(a = b = 1), do: %{a: a, b: b}

  def test_d(a = 1 = b), do: %{a: a, b: b}
end
