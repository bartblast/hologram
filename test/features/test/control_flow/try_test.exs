defmodule HologramFeatureTests.ControlFlow.TryTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ControlFlow.TryPage

  feature "rescue without a module", %{session: session} do
    session
    |> visit(TryPage)
    |> click(button("Rescue without a module"))
    |> assert_text(css("#result"), ":rescued_any")
  end

  feature "rescue with a single module", %{session: session} do
    session
    |> visit(TryPage)
    |> click(button("Rescue with a single module"))
    |> assert_text(css("#result"), ~s/{:rescued_single, "my message"}/)
  end

  feature "rescue with multiple modules", %{session: session} do
    session
    |> visit(TryPage)
    |> click(button("Rescue with multiple modules"))
    |> assert_text(css("#result"), ~s/{:rescued_multiple, "my message"}/)
  end

  feature "rescue unmatched module re-raises", %{session: session} do
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
