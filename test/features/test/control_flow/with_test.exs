defmodule HologramFeatureTests.ControlFlow.WithTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ControlFlow.WithPage

  # IMPORTANT!
  # Each feature test has a related JavaScript test in test/javascript/interpreter_test.mjs (with() section)
  # and a related Elixir consistency test in test/elixir/hologram/ex_js_consistency/with_test.exs.
  # Always update all three together.

  feature "evaluates the body when there are no clauses", %{session: session} do
    session
    |> visit(WithPage)
    |> click(button("Auxiliary"))
    |> assert_text(css("#result"), ":auxiliary")
    |> click(button("Empty with"))
    |> assert_text(css("#result"), "nil")
  end

  feature "returns the unmatched value when there are no else clauses", %{
    session: session
  } do
    session
    |> visit(WithPage)
    |> click(button("No else clauses passthrough"))
    |> assert_text(css("#result"), ":ok")
  end

  describe "match clauses" do
    feature "returns the body result for a single matching clause", %{
      session: session
    } do
      session
      |> visit(WithPage)
      |> click(button("Single matching clause"))
      |> assert_text(css("#result"), "{:ok, :ok}")
    end

    feature "returns the body result for multiple matching clauses", %{
      session: session
    } do
      session
      |> visit(WithPage)
      |> click(button("Multiple matching clauses"))
      |> assert_text(css("#result"), "{:ok, :ok}")
    end

    feature "returns the body result for a clause with a passing guard", %{
      session: session
    } do
      session
      |> visit(WithPage)
      |> click(button("Clause with passing guard"))
      |> assert_text(css("#result"), "{:ok, :ok}")
    end
  end

  describe "bare clauses" do
    feature "evaluates a bare expression clause that binds a variable", %{
      session: session
    } do
      session
      |> visit(WithPage)
      |> click(button("Bare clause that binds"))
      |> assert_text(css("#result"), "{:ok, :ok}")
    end

    feature "evaluates a bare expression clause that does not bind a variable", %{
      session: session
    } do
      session
      |> visit(WithPage)
      |> click(button("Bare clause that does not bind"))
      |> assert_text(css("#result"), "{:ok, :ok}")
    end

    feature "evaluates multiple bare expression clauses", %{session: session} do
      session
      |> visit(WithPage)
      |> click(button("Multiple bare clauses"))
      |> assert_text(css("#result"), "{:ok, :ok, :ok}")
    end

    feature "raises a MatchError when a bare clause fails to match", %{
      session: session
    } do
      assert_js_error session,
                      "(MatchError) no match of right hand side value: :ok",
                      fn ->
                        session
                        |> visit(WithPage)
                        |> click(button("Bare clause MatchError"))
                      end
    end
  end

  describe "else clauses" do
    feature "routes a failed match to a single else clause", %{session: session} do
      session
      |> visit(WithPage)
      |> click(button("Failed match to single else"))
      |> assert_text(css("#result"), ":match")
    end

    feature "selects the matching clause among multiple else clauses", %{
      session: session
    } do
      session
      |> visit(WithPage)
      |> click(button("Matching clause among multiple else"))
      |> assert_text(css("#result"), ":second")
    end

    feature "selects a guarded else clause when its guard passes", %{
      session: session
    } do
      session
      |> visit(WithPage)
      |> click(button("Guarded else clause"))
      |> assert_text(css("#result"), "{:guarded, :ok}")
    end

    feature "routes a failed guard to the else clauses", %{session: session} do
      session
      |> visit(WithPage)
      |> click(button("Failed guard to else"))
      |> assert_text(css("#result"), "{:error, :nomatch}")
    end

    feature "raises WithClauseError when no else clause matches", %{
      session: session
    } do
      assert_js_error session,
                      "(WithClauseError) no with clause matching: :ok",
                      fn ->
                        session
                        |> visit(WithPage)
                        |> click(button("No matching else clause"))
                      end
    end
  end

  describe "variable scoping" do
    feature "does not leak assignments into the original context", %{
      session: session
    } do
      session
      |> visit(WithPage)
      |> click(button("Does not leak"))
      |> assert_text(css("#result"), ":ok")
    end

    feature "evaluates else clauses in the original context", %{session: session} do
      session
      |> visit(WithPage)
      |> click(button("Else in original context"))
      |> assert_text(css("#result"), ":original")
    end

    feature "lets a later clause shadow an earlier binding", %{session: session} do
      session
      |> visit(WithPage)
      |> click(button("Later clause shadows"))
      |> assert_text(css("#result"), "3")
    end
  end
end
