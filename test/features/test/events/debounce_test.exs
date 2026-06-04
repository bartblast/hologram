defmodule HologramFeatureTests.Events.DebounceTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.DebouncePage

  feature "debounce coalesces a burst of events that an undebounced binding fires individually",
          %{session: session} do
    session
    |> visit(DebouncePage)
    |> fill_in(css("#my_input"), with: "abcde")
    |> assert_text(css("#plain_result"), ~s/{5, "e"}/)
    |> assert_text(css("#debounced_result"), ~s/{1, "e"}/)
  end
end
