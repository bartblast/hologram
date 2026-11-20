defmodule HologramFeatureTests.ServerTimeTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  require Hologram.Query

  alias Hologram.DB
  alias Hologram.Query
  alias HologramFeatureTests.Entities.Notice
  alias HologramFeatureTests.ServerTimePage

  setup do
    truncate_every_entity_table()

    :ok
  end

  # Mine is written while its batch is held, then theirs reaches the server, then mine does - the
  # order of an offline write and a message someone else sent meanwhile. The writer's time puts
  # mine first, the server's puts it last, and while it waits it has no server time and sorts as
  # the newest.
  feature "orders a row written before another arrived first by its writer's time and last by the server's",
          %{session: session} do
    session
    |> visit(ServerTimePage)
    |> await_local_fill()
    |> hold_mutation_requests()
    |> click(button("Write mine"))
    |> await_pending_writes(1)

    # Both rows' created_at hold milliseconds, so theirs is made a millisecond on at least - in the
    # same one, the writer's order would fall to their ids.
    Process.sleep(2)

    %{title: "theirs"}
    |> Notice.new()
    |> DB.create!()

    session
    |> await_local_read("Show order", "order", "mine, theirs | theirs, mine | mine")
    |> release_mutations()
    |> await_pending_writes(0)
    |> await_local_read("Show order", "order", "mine, theirs | theirs, mine | none")

    mine = read_notice("mine")
    theirs = read_notice("theirs")

    assert DateTime.compare(mine.created_at, theirs.server_created_at) == :lt
    assert DateTime.compare(theirs.server_created_at, mine.server_created_at) == :lt
  end

  defp read_notice(title) do
    Notice
    |> Query.filter(title == ^title)
    |> Query.one()
    |> DB.read()
  end
end
