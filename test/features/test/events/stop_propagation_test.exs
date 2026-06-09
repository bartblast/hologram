defmodule HologramFeatureTests.Events.StopPropagationTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.StopPropagationPage

  feature "stop_propagation keeps the outer binding from firing while a plain binding bubbles",
          %{session: session} do
    session
    |> visit(StopPropagationPage)
    |> click(css("#plain_button"))
    |> assert_text(css("#result"), "{true, true, false, false}")
    |> click(css("#stopped_button"))
    |> assert_text(css("#result"), "{true, true, true, false}")
  end
end
