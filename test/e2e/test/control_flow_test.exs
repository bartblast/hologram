defmodule HologramE2E.ControlFlowTest do
  use HologramE2E.TestCase, async: false

  feature "case expression", %{session: session} do
    session
    |> visit("/e2e/control-flow/case-expression")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 22"))
  end
end
