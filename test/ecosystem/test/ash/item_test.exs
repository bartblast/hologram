defmodule HologramEcosystemTests.Ash.ItemTest do
  use ExUnit.Case, async: false

  alias HologramEcosystemTests.Ash.Domain
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.Item.Admin
  alias HologramEcosystemTests.Ash.Note

  test "the fixtures are reached through their interfaces" do
    window = %{from: ~U[2026-01-01 00:00:00Z], to: ~U[2026-01-02 00:00:00Z]}

    item =
      Item.create!(%{
        available_on: ~D[2026-01-01],
        price: Money.new(:EUR, 10),
        title: "text",
        window: window
      })

    Note.create!(%{item_id: item.id, text: "note"})

    loaded = Item.get!(item.id, load: [:label, :note_count])

    assert loaded.label == "item: text"
    assert loaded.note_count == 1
    assert Money.equal?(loaded.price, Money.new(:EUR, 10))
    assert Domain.get_item!(item.id).id == item.id
    assert Enum.any?(Admin.list_all!(), &(&1.id == item.id))
    assert Item.summarize!(item.id) == "item #{item.id}"
    assert :ok = Item.archive!(loaded)
  end
end
