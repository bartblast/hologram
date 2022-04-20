defmodule HologramE2E.ControlFlowTest do
  use HologramE2E.TestCase, async: false

  describe "anonymous function call" do
    feature "regular syntax", %{session: session} do
      session
      |> visit("/e2e/control-flow/anonymous-function-call")
      |> click(css("#button_regular_syntax"))
      |> assert_has(css("#text", text: "Result = 6"))
    end

    # TODO: implement
    # feature "shorthand syntax"
  end

  feature "case expression", %{session: session} do
    session
    |> visit("/e2e/control-flow/case-expression")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 22"))
  end
end
