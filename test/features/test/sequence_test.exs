defmodule HologramFeatureTests.SequenceTest do
  # async: false - each test truncates the shared tables, and a held save holds every number above
  # it back for the whole app.
  use HologramFeatureTests.TestCase, async: false

  require Hologram.Query

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.Query
  alias HologramFeatureTests.Entities.Notice
  alias HologramFeatureTests.SequencePage

  setup do
    truncate_every_entity_table()

    :ok
  end

  # The held notice takes its number first and commits last. A browser marking read at the newest
  # number it holds would skip it, so the newer notice's number waits until the held one commits.
  feature "never moves a read marker past a save that is still running", %{session: session} do
    create_notice("first")

    session
    |> visit(SequencePage)
    |> await_local_fill()
    |> await_local_read("Show view", "view", "first | first | first | first")

    held = hold_save("held")

    create_notice("after")

    session
    |> await_local_read("Show view", "view", "first, after | after, first | first | first")
    |> click(button("Mark read"))
    |> await_local_read("Show view", "view", "first, after | after, first | first | none")

    assert read_notice("after").server_created_seq == nil

    release_save(held)

    await_local_read(
      session,
      "Show view",
      "view",
      "first, held, after | after, held, first | after | held, after"
    )

    assert read_notice("held").server_created_seq < read_notice("after").server_created_seq
  end

  # Mine waits unsent, then is saved while another save holds its number back, then theirs arrives
  # numbered above mine. Mine sorts at the newest end until its number is final, and no comparison
  # takes it before then.
  feature "sorts own rows at the newest end until their number is final", %{session: session} do
    create_notice("first")

    session
    |> visit(SequencePage)
    |> await_local_fill()
    |> await_local_read("Show view", "view", "first | first | first | first")
    |> click(button("Mark read"))
    |> await_local_read("Show view", "view", "first | first | first | none")
    |> hold_mutation_requests()
    |> click(button("Write mine"))
    |> await_pending_writes(1)
    |> await_local_read("Show view", "view", "first, mine | mine, first | first | none")

    held = hold_save("held")

    session
    |> release_mutations()
    |> await_pending_writes(0)

    create_notice("theirs")

    await_local_read(
      session,
      "Show view",
      "view",
      "first, theirs, mine | mine, theirs, first | first | none"
    )

    release_save(held)

    await_local_read(
      session,
      "Show view",
      "view",
      "first, held, mine, theirs | theirs, mine, held, first | theirs | held, mine, theirs"
    )
  end

  # The reload brings back the newer notice's number as waiting, from the store and from the page's
  # render alike, and files it once the held save commits.
  feature "holds a number back across a reload", %{session: session} do
    create_notice("first")

    session
    |> visit(SequencePage)
    |> await_local_fill()

    held = hold_save("held")

    create_notice("after")

    session
    |> await_local_read("Show view", "view", "first, after | after, first | first | first")
    |> await_durable_writes()
    |> reload()
    |> await_page_mount(SequencePage)
    |> assert_text(css("#view"), "first, after | after, first | first | first")
    |> await_local_fill()
    |> await_local_read("Show view", "view", "first, after | after, first | first | first")

    release_save(held)

    await_local_read(
      session,
      "Show view",
      "view",
      "first, held, after | after, held, first | after | first, held, after"
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

  defp read_notice(title) do
    Notice
    |> Query.filter(title == ^title)
    |> Query.one()
    |> DB.read()
  end
end
