defmodule HologramFeatureTests.SequenceTest do
  # async: false - each test truncates the shared tables, and a held save holds every number above
  # it back for the whole app.
  use HologramFeatureTests.TestCase, async: false

  require Hologram.Query

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Query
  alias Hologram.Sync.Dispatcher
  alias Hologram.Sync.FinalSeq
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
    |> visit(SequencePage, carried: :notices)
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
    |> visit(SequencePage, carried: :notices)
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

  # The reload's render hides the newer notice's number, as it isn't final, and the page carries it
  # as waiting. The page brought the row, so the browser takes no stored number into it, and the
  # lists leave the newer notice out until the held save commits.
  feature "holds a number back across a reload", %{session: session} do
    assert_number_held_across_reload(session, :notices)
  end

  # The page carries no notices, so the reload brings back the newer notice's number as waiting from
  # the store alone.
  feature "holds a stored number back across a reload", %{session: session} do
    assert_number_held_across_reload(session, :none)
  end

  # The first notice comes over the stream once the browser's point is past its numbers, so its
  # stored record holds them in its row, and the second moves the stored place past it, so the
  # reload's catch-up doesn't send it again. A node that just restarted publishes a limit below
  # every number, so the reload's render hides the first notice's numbers, and the page carries
  # them as waiting. The reload brings back the stored point, which is past them, so the browser
  # files them right away.
  feature "keeps a row's updated number across a reload rendered by a node that is behind",
          %{session: session} do
    session
    |> visit(SequencePage, carried: :notices)
    |> await_local_fill()

    first = create_notice("first")

    session
    |> await_local_read("Show updated", "updated", "first")
    |> await_stored_final(first)

    second = create_notice("second")

    stored =
      session
      |> await_local_read("Show updated", "updated", "first, second")
      |> await_stored_final(second)

    assert is_integer(stored_updated_seq(stored, first))
    assert stored_waiting_numbers(stored, first) == nil

    put_published_limit_behind()

    stored
    |> reload()
    |> await_page_mount(SequencePage)
    |> await_local_read("Show updated", "updated", "first, second")
  end

  defp assert_number_held_across_reload(session, carried) do
    create_notice("first")

    session
    |> visit(SequencePage, carried: carried)
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

  # Holds the node's published limit at 0, as a node that just restarted has it, until the test
  # ends. The dispatcher is suspended first, so it doesn't publish over it, and the limit is read
  # after, so it is the last one the dispatcher published. On exit the limit goes back before the
  # dispatcher resumes, since it only publishes above what it thinks it published.
  defp put_published_limit_behind do
    [dispatcher] =
      for {Dispatcher, pid, _type, _modules} <-
            Supervisor.which_children(Hologram.Sync.Supervisor),
          do: pid

    :sys.suspend(dispatcher)

    published = FinalSeq.published()

    on_exit(fn ->
      FinalSeq.publish(published)
      :sys.resume(dispatcher)
    end)

    FinalSeq.publish(0)
  end

  # The created number the stored record of the given notice keeps waiting beside it, or nil.
  defp stored_waiting_created_seq(session, notice) do
    session
    |> stored_value(notice, "record?.waiting?.numbers?.server_created_seq")
    |> then(&if(is_binary(&1), do: String.to_integer(&1), else: &1))
  end

  # Blocks until the stored record of the given notice holds its updated number in its row and
  # nothing waiting beside it, as one the stream brought once the browser's point passed it does.
  # The stored place is written in the same transaction as the record.
  defp await_stored_final(session, notice, attempts_left \\ 100)

  defp await_stored_final(session, notice, 0) do
    raise Wallaby.ExpectationNotMetError,
          "Timed out waiting for the stored record to hold its numbers final, it reads " <>
            inspect(stored_value(session, notice, "JSON.stringify(record)"))
  end

  defp await_stored_final(session, notice, attempts_left) do
    expression = "record?.row?.server_updated_seq != null && record?.waiting === undefined"

    if stored_value(session, notice, expression) do
      session
    else
      Process.sleep(50)
      await_stored_final(session, notice, attempts_left - 1)
    end
  end

  # The numbers the stored record of the given notice keeps waiting beside it, or nil.
  defp stored_waiting_numbers(session, notice) do
    stored_value(session, notice, "record?.waiting?.numbers")
  end

  # The updated number in the stored record's row of the given notice, or nil.
  defp stored_updated_seq(session, notice) do
    session
    |> stored_value(notice, "record?.row?.server_updated_seq")
    |> then(&if(is_binary(&1), do: String.to_integer(&1), else: &1))
  end

  # The value the given JavaScript expression reads from the stored record of the given notice,
  # bound as record, or nil.
  defp stored_value(session, notice, expression) do
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
          const record = reading.result;
          resolve((#{expression}) ?? null);
        };
      };
    }));
    """

    script_result(session, script)
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
