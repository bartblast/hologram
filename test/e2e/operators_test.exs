defmodule Hologram.Features.OperatorsTest do
  use Hologram.Test.E2ECase, async: false

  @moduletag :e2e

  feature "addition", %{session: session} do
    session
    |> visit("/e2e/operators/addition")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 3"))
  end

  feature "subtraction", %{session: session} do
    session
    |> visit("/e2e/operators/subtraction")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 4"))
  end
end
