defmodule HologramFeatureTests.SplitUpdateTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  require Hologram.Query

  alias Hologram.DB
  alias Hologram.Query
  alias HologramFeatureTests.Entities.Docket
  alias HologramFeatureTests.Entities.Sticker
  alias HologramFeatureTests.SplitUpdatePage

  setup do
    truncate_every_entity_table()

    %{status: "open"}
    |> Docket.new()
    |> DB.create!()

    sticker =
      %{name: "urgent"}
      |> Sticker.new()
      |> DB.create!()

    {:ok, sticker: sticker}
  end

  feature "lands a browser update that closes a docket its rule reads and sticks a sticker on it",
          %{session: session, sticker: sticker} do
    session
    |> visit(SplitUpdatePage)
    |> await_local_fill()
    |> click(button("Close and stick"))
    |> assert_text(css("#result"), "closed_and_stuck")
    |> await_pending_writes(0)

    # A refusal of the call would name what it refused here, rather than as a docket left open.
    assert script_result(session, "return globalThis.Hologram.writes.rejected();") == []

    dockets =
      Docket
      |> Query.include(stickers)
      |> DB.read()

    assert [%Docket{status: "closed", stickers: [%Sticker{id: sticker_id}]}] = dockets
    assert sticker_id == sticker.id
  end
end
