defmodule Hologram.Features.EventsTest do
  use Hologram.Test.E2ECase, async: false

  @moduletag :e2e

  feature "blur event", %{session: session} do
    session
    |> visit("/e2e/page-11")
    |> click(css("#input"))
    |> click(css("#text"))
    |> assert_has(css("#text", text: "Field has been blurred"))
  end

  feature "change event", %{session: session} do
    session
    |> visit("/e2e/page-10")
    |> fill_in(css("#input-1"), with: "abc")
    |> fill_in(css("#input-2"), with: "xyz")
    |> click(css("#text-1")) # triggers change event, since #input-2 loses focus
    |> assert_has(css("#text-1", text: "Field 1 value = abc"))
    |> assert_has(css("#text-2", text: "Field 2 value = xyz"))
  end

  feature "click event", %{session: session} do
    session
    |> visit("/e2e/page-2")
    |> click(css("#page-2-update-text-button"))
    |> assert_has(css("#page-2-text", text: "text updated by page 2 update button"))
  end

  feature "pointer down event", %{session: session} do
    session
    |> visit("/e2e/page-12")
    |> click(css("#target"))
    |> assert_has(css("#text", text: "Event count: 1"))
    |> touch_down(css("#target"))
    |> assert_has(css("#text", text: "Event count: 2"))
  end

  feature "submit event", %{session: session} do
    session
    |> visit("/e2e/page-8")
    |> fill_in(css("#input-1"), with: "abc")
    |> fill_in(css("#input-2"), with: "xyz")
    |> click(css("#submit-button"))
    |> assert_has(css("#text-1", text: "Field 1 value = abc"))
    |> assert_has(css("#text-2", text: "Field 2 value = xyz"))
  end
end
