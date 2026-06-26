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
end
