defmodule HologramFeatureTests.Events.KeyboardTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.KeyboardPage

  feature "key down", %{session: session} do
    session
    |> visit(KeyboardPage)
    |> fill_in(css("#my_input_key_down"), with: "a")
    |> assert_text(
      css("#result"),
      ~r/\{:key_down, %\{event: %\{alt_key: false, code: "KeyA", ctrl_key: false, key: "a", meta_key: false, repeat: false, shift_key: false\}\}\}/
    )
  end

  feature "key up", %{session: session} do
    session
    |> visit(KeyboardPage)
    |> fill_in(css("#my_input_key_up"), with: "a")
    |> assert_text(
      css("#result"),
      ~r/\{:key_up, %\{event: %\{alt_key: false, code: "KeyA", ctrl_key: false, key: "a", meta_key: false, repeat: false, shift_key: false\}\}\}/
    )
  end
end
