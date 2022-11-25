defmodule HologramE2E.EventsTest do
  use HologramE2E.TestCase, async: false

  alias HologramE2E.Page2
  alias HologramE2E.Page8
  alias HologramE2E.Page10
  alias HologramE2E.Page11
  alias HologramE2E.Page12
  alias HologramE2E.Page13

  feature "blur event", %{session: session} do
    session
    |> visit(Page11)
    |> click(css("#input"))
    |> click(css("#text"))
    |> assert_has(css("#text", text: "Field has been blurred"))
  end

  feature "change event", %{session: session} do
    session
    |> visit(Page10)
    |> fill_in(css("#input-1"), with: "abc")
    |> fill_in(css("#input-2"), with: "xyz")
    # triggers change event, since #input-2 loses focus
    |> click(css("#text-1"))
    |> assert_has(css("#text-1", text: "Field 1 value = abc"))
    |> assert_has(css("#text-2", text: "Field 2 value = xyz"))
  end

  feature "click event", %{session: session} do
    session
    |> visit(Page2)
    |> click(css("#page-2-update-text-button"))
    |> assert_has(css("#page-2-text", text: "text updated by page 2 update button"))
  end

  feature "pointer down event", %{session: session} do
    # for some reason Wallaby doesn't generate pointerdown event on touch down
    js = "document.getElementById('target').dispatchEvent(new Event('pointerdown'))"

    session
    |> visit(Page12)
    |> click(css("#target"))
    |> assert_has(css("#text", text: "Event count: 1"))
    |> execute_script(js)
    |> assert_has(css("#text", text: "Event count: 2"))
  end

  feature "pointer up event", %{session: session} do
    # for some reason Wallaby doesn't generate pointerup event on touch down
    js = "document.getElementById('target').dispatchEvent(new Event('pointerup'))"

    session
    |> visit(Page13)
    |> click(css("#target"))
    |> assert_has(css("#text", text: "Event count: 1"))
    |> execute_script(js)
    |> assert_has(css("#text", text: "Event count: 2"))
  end

  feature "submit event", %{session: session} do
    session
    |> visit(Page8)
    |> fill_in(css("#input-1"), with: "abc")
    |> fill_in(css("#input-2"), with: "xyz")
    |> click(css("#submit-button"))
    |> assert_has(css("#text-1", text: "Field 1 value = abc"))
    |> assert_has(css("#text-2", text: "Field 2 value = xyz"))
  end
end
