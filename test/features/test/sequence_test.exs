defmodule HologramFeatureTests.SequenceTest do
  # async: false - each test truncates the shared tables, and a held save holds every number above
  # it back for the whole app.
  use HologramFeatureTests.TestCase, async: false

  require Hologram.Query

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Query
  alias HologramFeatureTests.Entities.Notice
  alias HologramFeatureTests.SequencePage

  setup do
    truncate_every_entity_table()

    :ok
  end

  # The held notice takes its number first and commits last. A browser marking read at the newest
  # number it holds would skip it, so the newer notice's number waits until the held one commits,
  # and the lists ordered by it leave the newer notice out until then.
  feature "never moves a read marker past a save that is still running", %{session: session} do
    create_notice("first")

    session
    |> visit(SequencePage)
    |> await_local_fill()
    |> await_local_read("Show view", "view", "first | first | first | first | first")

    held = hold_save("held")

    create_notice("after")

    session
    |> await_local_read("Show view", "view", "first | first | first | first | after, first")
    |> click(button("Mark read"))
    |> await_local_read("Show view", "view", "first | first | first | none | after, first")

    assert read_notice("after").server_created_seq == nil

    release_save(held)

    await_local_read(
      session,
      "Show view",
      "view",
      "first, held, after | after, held, first | after | held, after | after, first, held"
    )

    held_seq = read_notice("held").server_created_seq
    after_seq = read_notice("after").server_created_seq

    assert is_integer(held_seq)
    assert is_integer(after_seq)
    assert held_seq < after_seq
  end

  # Mine waits unsent, then is saved while another save holds its number back, then theirs arrives
  # numbered above mine. Mine sorts at the newest end until its number is final, and no comparison
  # takes it before then, while theirs stays out of the lists until its number is final.
  feature "sorts own rows at the newest end until their number is final", %{session: session} do
    create_notice("first")

    session
    |> visit(SequencePage)
    |> await_local_fill()
    |> await_local_read("Show view", "view", "first | first | first | first | first")
    |> click(button("Mark read"))
    |> await_local_read("Show view", "view", "first | first | first | none | first")
    |> hold_mutation_requests()
    |> click(button("Write mine"))
    |> await_pending_writes(1)
    |> await_local_read(
      "Show view",
      "view",
      "first, mine | mine, first | first | none | first, mine"
    )

    held = hold_save("held")

    session
    |> release_mutations()
    |> await_pending_writes(0)

    create_notice("theirs")

    await_local_read(
      session,
      "Show view",
      "view",
      "first, mine | mine, first | first | none | first, mine, theirs"
    )

    release_save(held)

    await_local_read(
      session,
      "Show view",
      "view",
      "first, held, mine, theirs | theirs, mine, held, first | theirs | held, mine, theirs | " <>
        "first, held, mine, theirs"
    )
  end

  # The reload brings back the newer notice's number as waiting, from the store and from the page's
  # render alike, so the lists leave it out until the held save commits.
  feature "holds a number back across a reload", %{session: session} do
    create_notice("first")

    session
    |> visit(SequencePage)
    |> await_local_fill()

    held = hold_save("held")

    after_notice = create_notice("after")

    stored =
      session
      |> await_local_read("Show view", "view", "first | first | first | first | after, first")
      |> await_durable_writes()

    assert stored_waiting_created_seq(stored, after_notice) == raw_created_seq(after_notice)

    stored
    |> reload()
    |> await_page_mount(SequencePage)
    |> assert_text(css("#view"), "first | first | first | first | after, first")
    |> await_local_fill()
    |> await_local_read("Show view", "view", "first | first | first | first | after, first")

    release_save(held)

    await_local_read(
      session,
      "Show view",
      "view",
      "first, held, after | after, held, first | after | first, held, after | " <>
        "after, first, held"
    )
  end

  defp create_notice(title) do
    %{title: title}
    |> Notice.new()
    |> DB.create!()
  end

  # Creates a notice in a transaction left open until release_save/1, so its number is taken and
  # every number after it waits.
  defp hold_save(title) do
    test_pid = self()

    task =
      Task.async(fn ->
        Connection.transaction(fn ->
          create_notice(title)
          send(test_pid, :saved)

          receive do
            :release -> :ok
          end
        end)
      end)

    assert_receive :saved, 5_000

    task
  end

  defp release_save(task) do
    send(task.pid, :release)

    assert {:ok, :ok} = Task.await(task)
  end

  # The created number the stored record of the given notice keeps waiting beside it, or nil.
  defp stored_waiting_created_seq(session, notice) do
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
          .get(["#{inspect(Notice)}", "#{notice.id}"]);

        reading.onerror = () => reject(reading.error);

        reading.onsuccess = () => {
          db.close();
          resolve(reading.result?.waiting?.numbers?.server_created_seq ?? null);
        };
      };
    }));
    """

    session
    |> script_result(script)
    |> then(&if(is_binary(&1), do: String.to_integer(&1), else: &1))
  end

  # The notice's created number as the table holds it, which a server read masks while it waits.
  defp raw_created_seq(notice) do
    {:ok, %{rows: [[seq]]}} =
      Connection.query(
        ~s(SELECT "server_created_seq" FROM "hologram_data"."#{Mapper.table_name(Notice)}" ) <>
          ~s(WHERE "id"::text = $1),
        [notice.id]
      )

    seq
  end

  defp read_notice(title) do
    Notice
    |> Query.filter(title == ^title)
    |> Query.one()
    |> DB.read()
  end
end
