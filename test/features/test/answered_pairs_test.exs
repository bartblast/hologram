defmodule HologramFeatureTests.AnsweredPairsTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.AnsweredPairsPage
  alias HologramFeatureTests.Entities.Binder
  alias HologramFeatureTests.Entities.Decal

  setup do
    truncate_every_entity_table()

    binder =
      %{name: "main", note: "a"}
      |> Binder.new()
      |> DB.create!()

    decal =
      %{name: "red"}
      |> Decal.new()
      |> DB.create!()

    {:ok, binder: binder, decal: decal}
  end

  # A query passes over a pair naming a row the browser doesn't hold, so the page can't show one.
  # A frame writing the binder stores its sets as the browser holds them, so the store does.
  defp assert_binder_stores_no_decal(session, binder) do
    DB.update!(Binder, binder.id, note: "b")

    stored =
      session
      |> assert_text(css("#binders"), "main(b)[]")
      |> await_durable_writes()

    assert stored_decals(stored, binder) == []
  end

  defp stored_decals(session, binder) do
    script = """
    return indexedDB.databases().then((databases) => new Promise((resolve, reject) => {
      const name = databases
        .map((database) => database.name)
        .find((name) => name.startsWith("hologram."));

      const opening = indexedDB.open(name);

      opening.onerror = () => reject(opening.error);

      opening.onsuccess = () => {
        const db = opening.result;

        const reading = db
          .transaction("entities")
          .objectStore("entities")
          .get(["#{inspect(Binder)}", "#{binder.id}"]);

        reading.onerror = () => reject(reading.error);

        reading.onsuccess = () => {
          db.close();
          resolve(reading.result.facts.decals);
        };
      };
    }));
    """

    script_result(session, script)
  end

  feature "a pair added to a row that left while its batch waited isn't kept",
          %{binder: binder, decal: decal, session: session} do
    session
    |> visit(AnsweredPairsPage)
    |> await_local_fill()
    |> assert_text(css("#decals"), ~r/^red$/)
    |> hold_mutation_requests()
    |> click(button("Add decal"))
    |> assert_text(css("#binders"), "main(a)[red]")

    DB.update!(Decal, decal.id, shown: false)

    session
    |> assert_text(css("#decals"), ~r/^$/)
    |> await_pending_writes(1)
    |> release_mutations()
    |> await_pending_writes(0)
    |> assert_binder_stores_no_decal(binder)
  end

  feature "a pair whose answer overtook the row's drop isn't kept",
          %{binder: binder, decal: decal, session: session} do
    filled =
      session
      |> visit(AnsweredPairsPage)
      |> await_local_fill()
      |> assert_text(css("#decals"), ~r/^red$/)
      |> hold_sync_frames()

    filled
    |> current_instance_id()
    |> simulate_sse_disconnect()

    await_held_all_marker(filled)

    DB.update!(Decal, decal.id, shown: false)

    # Held until the session has read the drop, so the batch commits after the pairs the drop tells
    # were read, and answered before the drop lands.
    filled
    |> await_held(
      ~s|event.type === "sync_deltas" && JSON.parse(event.data).deltas.unsync_entity?.["#{inspect(Decal)}"]?.includes("#{decal.id}")|
    )
    |> hold_mutation_requests()
    |> click(button("Add decal"))
    |> await_pending_writes(1)
    |> release_mutations()
    |> await_pending_writes(0)
    |> release_sync_frames()
    |> assert_text(css("#decals"), ~r/^$/)
    |> assert_binder_stores_no_decal(binder)
  end
end
