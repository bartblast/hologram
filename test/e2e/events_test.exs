defmodule Hologram.Features.EventsTest do
  use Hologram.Test.E2ECase, async: false

  @moduletag :e2e

  feature "click event", %{session: session} do
    session
    |> visit("/e2e/page-2")
    |> click(css("#page-2-update-text-button"))
    |> assert_has(css("#text", text: "updated text"))
  end
end
