defmodule HologramFeatureTests.Events.ThrottleTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.Throttle.Page1
  alias HologramFeatureTests.Events.Throttle.Page2
  alias HologramFeatureTests.Events.Throttle.Page3

  feature "throttle caps a burst to a leading and trailing dispatch while a plain binding fires on every event",
          %{session: session} do
    session
    |> visit(Page1)
    |> fill_in(css("#my_input"), with: "abcde")
    |> assert_text(css("#plain_result"), ~s/{5, "e"}/)
    |> assert_text(css("#throttled_result"), ~s/{2, "e"}/)
  end

  # Positive control for the cancellation scenario below: the same two hovers queue a trailing
  # dispatch that fires when the user stays on the page.
  feature "a held trailing throttled dispatch fires while the user stays on the page",
          %{session: session} do
    session
    |> visit(Page2)
    |> hover(css("#hover_zone"))
    |> assert_text(css("#layout_result"), "1")
    |> hover(css("#hover_zone_inner"))
    |> assert_text(css("#layout_result"), "2")
  end

  # The result reaching 1 proves the leading edge fired and the window is open, so the second
  # hover is held for the trailing edge. The layout is re-rendered on the destination page with a
  # fresh count, so waiting out the rest of the window there proves the held dispatch was
  # cancelled rather than delayed - a post-navigation fire would bump the fresh count.
  feature "navigating to another page cancels a held trailing throttled dispatch",
          %{session: session} do
    session
    |> visit(Page2)
    |> hover(css("#hover_zone"))
    |> assert_text(css("#layout_result"), "1")
    |> hover(css("#hover_zone_inner"))
    |> click(link("Page 3 link"))
    |> assert_page(Page3)
    |> sleep(3_000)
    |> assert_text(css("#layout_result"), "0")
  end

  # The same guarantee down the history handler rather than the page swap, which is a separate
  # entry point with its own cancellation. Two independent things keep the held dispatch off the
  # restored page - it is cancelled when the page is left, and were it not, it carries the epoch
  # of the page it was held on and would be dropped on settling - so this passes with either one
  # alone. It is here to hold the pair on this path, not to single out the cancellation.
  feature "going back to another page cancels a held trailing throttled dispatch",
          %{session: session} do
    session
    |> visit(Page3)
    |> click(link("Page 2 link"))
    |> assert_page(Page2)
    |> hover(css("#hover_zone"))
    |> assert_text(css("#layout_result"), "1")
    |> hover(css("#hover_zone_inner"))
    |> go_back()
    |> assert_page(Page3)
    |> sleep(3_000)
    |> assert_text(css("#layout_result"), "0")
  end
end
