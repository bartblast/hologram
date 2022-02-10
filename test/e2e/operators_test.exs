defmodule Hologram.Features.OperatorsTest do
  use Hologram.Test.E2ECase, async: false

  @moduletag :e2e

  feature "subtraction operator", %{session: session} do
    session
    |> visit("/e2e/page-14")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "Result = 4"))
  end
end
