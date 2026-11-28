defmodule HologramFeatureTests.UpdateSyntaxTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.UpdateSyntaxPage

  feature "missing key", %{session: session} do
    assert_client_error session, KeyError, "key :x not found", fn ->
      session
      |> visit(UpdateSyntaxPage)
      |> click(css("button[id='missing key']"))
    end
  end

  # TODO: expect the BEAM form, %HologramFeatureTests.UpdateSyntaxStructFixture{limit: 3, other: 99},
  # once struct inspect is implemented (see the "TODO: inspect structs" note on
  # Interpreter.#inspectMap/2 in assets/js/interpreter.mjs).
  feature "struct update", %{session: session} do
    session
    |> visit(UpdateSyntaxPage)
    |> click(css("button[id='struct update']"))
    |> assert_text(
      css("#result"),
      ~s(%{__struct__: HologramFeatureTests.UpdateSyntaxStructFixture, limit: 3, other: 99})
    )
  end
end
