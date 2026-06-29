defmodule HologramFeatureTests.Events.OnceTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.OncePage

  feature "fires the action once, then stops re-dispatching", %{session: session} do
    session
    |> visit(OncePage)
    |> click(css("#click_button"))
    |> click(css("#click_button"))
    |> click(css("#click_button"))
    |> assert_text(css("#click_result"), "1")
  end

  feature "stays spent across re-renders but re-arms when the element is re-created",
          %{session: session} do
    session
    |> visit(OncePage)
    |> click(css("#rearm_button"))
    # An unrelated re-render keeps the element in place, so the binding stays spent.
    |> click(css("#rerender_button"))
    |> click(css("#rearm_button"))
    |> assert_text(css("#rearm_result"), "1")
    # Hiding then showing the element re-creates it, which re-arms the binding.
    |> click(css("#toggle_button"))
    |> click(css("#toggle_button"))
    |> click(css("#rearm_button"))
    |> assert_text(css("#rearm_result"), "2")
  end
end
