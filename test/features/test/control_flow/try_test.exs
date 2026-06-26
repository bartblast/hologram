defmodule HologramFeatureTests.ControlFlow.TryTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ControlFlow.TryPage

  describe "rescue clauses" do
    feature "without a module", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Rescue without a module"))
      |> assert_text(css("#result"), ":rescued_any")
    end

    feature "with a single module", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Rescue with a single module"))
      |> assert_text(css("#result"), ~s/{:rescued_single, "my message"}/)
    end

    feature "with multiple modules", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Rescue with multiple modules"))
      |> assert_text(css("#result"), ~s/{:rescued_multiple, "my message"}/)
    end

    feature "unmatched module re-raises", %{session: session} do
      assert_client_error session,
                          RuntimeError,
                          "my message",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("Rescue unmatched module"))
                          end
    end
  end

  describe "catch clauses" do
    feature "throw kind", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Catch throw"))
      |> assert_text(css("#result"), ~s/{:caught_throw, "my value"}/)
    end

    feature "exit kind", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Catch exit"))
      |> assert_text(css("#result"), ~s/{:caught_exit, "my reason"}/)
    end

    feature "error kind", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Catch error"))
      |> assert_text(css("#result"), ~s/{:caught_error, "my message"}/)
    end

    feature "unmatched kind re-raises", %{session: session} do
      assert_client_error session,
                          RuntimeError,
                          "my message",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("Catch unmatched kind"))
                          end
    end
  end

  describe "else clauses" do
    feature "matches the do result", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("Else with a match"))
      |> assert_text(css("#result"), ":else_two")
    end

    feature "raises TryClauseError when no clause matches", %{session: session} do
      assert_client_error session,
                          TryClauseError,
                          "no try clause matching:\n\n    :no_match\n",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("Else without a match"))
                          end
    end
  end

  describe "after block" do
    feature "keeps the do result", %{session: session} do
      session
      |> visit(TryPage)
      |> click(button("After keeps result"))
      |> assert_text(css("#result"), ":body_result")
    end

    feature "runs on the success path", %{session: session} do
      assert_client_error session,
                          RuntimeError,
                          "after ran",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("After runs on success"))
                          end
    end

    feature "runs on the failure path", %{session: session} do
      assert_client_error session,
                          RuntimeError,
                          "after ran",
                          fn ->
                            session
                            |> visit(TryPage)
                            |> click(button("After runs on failure"))
                          end
    end
  end
end
