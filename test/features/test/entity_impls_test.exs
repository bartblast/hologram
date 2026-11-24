defmodule HologramFeatureTests.EntityImplsTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.Entities.Bottle
  alias HologramFeatureTests.Entities.Crate
  alias HologramFeatureTests.Entities.Event
  alias HologramFeatureTests.Entities.Jar
  alias HologramFeatureTests.Entities.Lid
  alias HologramFeatureTests.Entities.Pantry
  alias HologramFeatureTests.EntityImpls.Page1
  alias HologramFeatureTests.EntityImpls.Page2
  alias HologramFeatureTests.EntityImpls.Page3
  alias HologramFeatureTests.EntityImpls.Page4

  setup do
    truncate_entity_tables([Bottle, Crate, Event, Jar, Lid, Pantry])

    :ok
  end

  defp create!(type, attrs) do
    attrs
    |> type.new()
    |> DB.create!()
  end

  feature "prints a synced row with the implementation of a type the page doesn't name", %{
    session: session
  } do
    crate = create!(Crate, name: "north")
    bottle = create!(Bottle, crate_id: crate.id, label: "ale")

    session
    |> visit(Page1)
    |> await_local_fill()
    |> assert_text(css("#crates"), ~r/^north:ale$/)
    |> mark_this_page_load()

    DB.update!(Bottle, bottle.id, label: "beer")

    session
    |> assert_text(css("#crates"), ~r/^north:beer$/)
    |> assert_same_page_load()
  end

  feature "syncs a type only the implementation of a row's type names", %{session: session} do
    pantry = create!(Pantry, name: "cellar")
    create!(Jar, label: "plum", pantry_id: pantry.id)
    create!(Lid, sealed: true)

    session
    |> visit(Page2)
    |> await_local_fill()
    |> assert_text(css("#sealed_lids"), ~r/^1$/)
    |> mark_this_page_load()

    create!(Lid, sealed: true)

    session
    |> assert_text(css("#sealed_lids"), ~r/^2$/)
    |> assert_same_page_load()
  end

  feature "prints a synced row's date and system datetime", %{session: session} do
    event = create!(Event, held_on: ~D[2026-03-01], name: "alpha")

    session
    |> visit(Page3)
    |> await_local_fill()
    |> assert_text(css("#events"), ~r/^alpha\|2026-03-01\|\d{4}-\d{2}-\d{2} /)
    |> mark_this_page_load()

    DB.update!(Event, event.id, name: "bravo")

    session
    |> assert_text(css("#events"), ~r/^bravo\|2026-03-01\|\d{4}-\d{2}-\d{2} /)
    |> assert_same_page_load()
  end

  feature "builds a struct from the module of a synced row", %{session: session} do
    pantry = create!(Pantry, name: "cellar")
    jar = create!(Jar, label: "plum", pantry_id: pantry.id)

    session
    |> visit(Page4)
    |> await_local_fill()
    |> assert_text(css("#jars"), ~r/^plum:copy$/)
    |> mark_this_page_load()

    DB.update!(Jar, jar.id, label: "quince")

    session
    |> assert_text(css("#jars"), ~r/^quince:copy$/)
    |> assert_same_page_load()
  end
end
