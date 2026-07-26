defmodule HologramFeatureTests.Events.MultipleBindingsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.MultipleBindingsPage

  feature "bindings for the same event run in the order they are written",
          %{session: session} do
    session
    |> visit(MultipleBindingsPage)
    |> click(css("#order_button"))
    |> assert_text(css("#order_result"), "[:first, :second]")
  end

  feature "several key filters on one element each fire only on their own key",
          %{session: session} do
    session
    |> visit(MultipleBindingsPage)
    |> send_keys(css("#filter_input"), [:enter])
    |> assert_text(css("#filter_result"), ":enter_matched")
    |> send_keys(css("#filter_input"), [:escape])
    |> assert_text(css("#filter_result"), ":escape_matched")
  end

  feature "two debounced bindings with different windows on the same event each fire independently",
          %{session: session} do
    session
    |> visit(MultipleBindingsPage)
    |> fill_in(css("#layered_input"), with: "layered")
    # Observed between the two windows: the quick binding has already fired while the full one is
    # still pending, proving the windows are distinct rather than both dispatching together.
    |> assert_text(css("#quick_result"), ~s/"layered"/)
    |> assert_text(css("#full_result"), "nil")
    |> assert_text(css("#full_result"), ~s/"layered"/)
  end
end
