defmodule HologramE2E.ControlFlowTest do
  use HologramE2E.TestCase, async: false

  @moduletag :e2e

  feature "case expression", %{session: session} do
    session
    |> visit("/e2e/operators/addition")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 3"))
  end
