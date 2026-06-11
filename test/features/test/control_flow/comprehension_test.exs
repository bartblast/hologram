defmodule HologramFeatureTests.ControlFlow.ComprehensionTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ControlFlow.ComprehensionPage

  # IMPORTANT!
  # Each feature test has a related JavaScript test in test/javascript/interpreter_test.mjs
  # (comprehension() and comprehensionReduce() sections)
  # and a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/comprehension_test.exs.
  # Always update all three together.
  #
  # The mirroring is not complete yet - this file covers only the dependent-generator,
  # position-sensitive-filter, bitstring generator, and reducer tests.

  # TODO: mirror the remaining behavioral tests from the comprehension() section
  # of test/javascript/interpreter_test.mjs:
  # - enumerable generator: generates combinations of enumerables items
  # - enumerable generator: ignores enumerable items that don't match the pattern
  # - bitstring generator: matches segments narrower than a byte
  # - bitstring generator: generates combinations of bitstring generators
  # - bitstring generator: can use variables bound by an earlier generator
  # - bitstring generator: returns an empty result for an empty bitstring
  # - bitstring generator: removes duplicate results when the unique flag is set
  # - bitstring generator: raises ErlangError if the source is not a bitstring
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

  describe "enumerable generator" do
    feature "can use variables bound by an earlier generator", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Dependent generator"))
      |> assert_text(css("#result"), "[{1, 1}, {1, 11}, {2, 2}, {2, 12}]")
    end
  end

  describe "bitstring generator" do
    feature "iterates in pattern-sized steps", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Basic bitstring generator"))
      |> assert_text(css("#result"), "[5, 6, 7]")
    end

    feature "binds multiple segments per step", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Bitstring generator with multi-segment pattern"))
      |> assert_text(css("#result"), "[{1, 2}, {3, 4}]")
    end

    feature "stops iterating at the first non-matching prefix", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Bitstring generator with prefix mismatch"))
      |> assert_text(css("#result"), "[2]")
    end

    feature "discards leftover bits that don't fill the pattern", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Bitstring generator with leftover bits"))
      |> assert_text(css("#result"), "[1, 2]")
    end

    feature "composes with filters", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Bitstring generator with filter"))
      |> assert_text(css("#result"), "[1, 3]")
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

  describe "reducer" do
    feature "accumulates over a single enumerable generator", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Reducer with single generator"))
      |> assert_text(css("#result"), "6")
    end

    feature "accumulates over a bitstring generator", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Reducer with bitstring generator"))
      |> assert_text(css("#result"), "9")
    end

    feature "accumulates over multiple enumerable generators", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Reducer with multiple generators"))
      |> assert_text(css("#result"), "90")
    end

    feature "returns the initial value when the enumerable generator is empty", %{
      session: session
    } do
      session
      |> visit(ComprehensionPage)
      |> click(button("Reducer with empty generator"))
      |> assert_text(css("#result"), "100")
    end

    feature "returns the initial value when filters reject all items", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Reducer with all-rejecting filter"))
      |> assert_text(css("#result"), "200")
    end

    feature "filters limit which items update the accumulator", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Reducer with selective filter"))
      |> assert_text(css("#result"), "306")
    end

    feature "dispatches to the clause matching the accumulator", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Reducer with clause dispatch"))
      |> assert_text(css("#result"), "123")
    end

    feature "dispatches to the clause whose guards pass", %{session: session} do
      session
      |> visit(ComprehensionPage)
      |> click(button("Reducer with guard dispatch"))
      |> assert_text(css("#result"), "33")
    end

    feature "reducer clauses can access variables from comprehension outer scope", %{
      session: session
    } do
      session
      |> visit(ComprehensionPage)
      |> click(button("Reducer with outer scope access"))
      |> assert_text(css("#result"), "32")
    end

    feature "raises CaseClauseError when no clause matches the accumulator", %{session: session} do
      assert_js_error session,
                      "(CaseClauseError) no case clause matching:\n\n    0",
                      fn ->
                        session
                        |> visit(ComprehensionPage)
                        |> click(button("Reducer with unmatched accumulator"))
                      end
    end
  end
end
