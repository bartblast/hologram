
defmodule Hologram.Features.CommandsTest do
  use Hologram.E2ECase, async: true

  @moduletag :e2e

  feature "command without params that returns action without params", %{session: session} do
    session
    |> visit("/e2e/page-1")
    |> click(css("#button"))
    |> assert_has(css("#text", text: "test updated text"))
  end

  # TODO: implement other cases
end
