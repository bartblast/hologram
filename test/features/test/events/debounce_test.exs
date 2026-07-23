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

  # The debounce window is far longer than the assertion timeout, so the result can only appear
  # through the blur flush, never through the window elapsing.
  feature "blurring the input flushes its pending debounced dispatch", %{session: session} do
    session
    |> visit(DebouncePage)
    |> fill_in(css("#blur_input"), with: "holo")
    |> click(css("#my_input"))
    |> assert_text(css("#blurred_result"), ~s/"holo"/)
  end

  # Submitting via Enter keeps focus in the input, so no blur flush kicks in beforehand - the
  # submit action can only observe the typed value if the submit flush ran the pending change
  # dispatch first.
  feature "submitting the form flushes its pending debounced dispatches first",
          %{session: session} do
    session
    |> visit(DebouncePage)
    |> fill_in(css("#submit_input"), with: "flush")
    |> send_keys([:enter])
    |> assert_text(css("#submitted_result"), ~s/"flush"/)
  end
end
