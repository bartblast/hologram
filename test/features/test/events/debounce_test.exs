defmodule HologramFeatureTests.Events.DebounceTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.Debounce.Page1
  alias HologramFeatureTests.Events.Debounce.Page2
  alias HologramFeatureTests.Events.Debounce.Page3

  feature "debounce coalesces a burst of events that an undebounced binding fires individually",
          %{session: session} do
    session
    |> visit(Page1)
    |> fill_in(css("#my_input"), with: "abcde")
    |> assert_text(css("#plain_result"), ~s/{5, "e"}/)
    |> assert_text(css("#debounced_result"), ~s/{1, "e"}/)
  end

  # The debounce window is far longer than the assertion timeout, so the result can only appear
  # through the blur flush, never through the window elapsing.
  feature "blurring the input flushes its pending debounced dispatch", %{session: session} do
    session
    |> visit(Page1)
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
    |> visit(Page1)
    |> fill_in(css("#submit_input"), with: "flush")
    |> send_keys([:enter])
    |> assert_text(css("#submitted_result"), ~s/"flush"/)
  end

  # The pending dispatch is keyed on the hover zone, which never has focus, so no blur flush runs
  # when the link is clicked - the dispatch is still pending when navigation happens. Waiting out
  # the rest of the window on the destination page proves the dispatch was cancelled rather than
  # delayed: the layout is re-rendered there, so a post-navigation fire would show up in its result.
  feature "navigating to another page cancels a pending debounced dispatch",
          %{session: session} do
    session
    |> visit(Page2)
    |> hover(css("#hover_zone"))
    |> click(link("Page 3 link"))
    |> assert_page(Page3)
    |> sleep(3_000)
    |> assert_text(css("#layout_result"), "nil")
  end
end
