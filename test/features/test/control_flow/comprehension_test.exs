defmodule HologramFeatureTests.ControlFlow.ComprehensionTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ControlFlow.ComprehensionPage

  # IMPORTANT!
  # Each feature test has a related JavaScript test in test/javascript/interpreter_test.mjs (comprehension() section)
  # and a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/comprehension_test.exs.
  # Always update all three together.
  #
  # The mirroring is not complete yet - this file covers only the dependent-generator
  # and position-sensitive-filter tests.

  # TODO: mirror the remaining behavioral tests from the comprehension() section
  # of test/javascript/interpreter_test.mjs:
  # - generator: generates combinations of enumerables items
  # - generator: ignores enumerable items that don't match the pattern
  # - guards: single guard
  # - guards: multiple guards
  # - guards: can access variables from comprehension outer scope
  # - guards: can access variables pattern matched in preceding guards
  # - guards: errors raised inside generators are not caught
  # - filters: remove combinations that don't fullfill specified conditions
  # - filters: can access variables from comprehension outer scope
  # - unique: non-unique items are removed if 'uniq' option is set to true
  # - mapper: can access variables from comprehension outer scope
  # - mapper: uses Enum.into/2 to insert the comprehension result into a collectable

  describe "generator" do
    feature "can use variables bound by an earlier generator", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Dependent generator"))
      |> assert_text(css("#result"), "[{1, 1}, {1, 11}, {2, 2}, {2, 12}]")
    end
  end

  describe "filters" do
    feature "placed between generators prunes the branch before the next generator runs", %{
      session: session
    } do
      session
      |> visit(ComprehensionPage)
      |> click(button("Guarding filter"))
      |> assert_text(css("#result"), "[1, 2, 3]")
    end
  end
end
