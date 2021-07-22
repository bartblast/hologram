defmodule Hologram.Features.RuntimeTest do
  use Hologram.E2ECase, async: true

  @moduletag :e2e

  feature "command", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "test updated text"))
  end
end
