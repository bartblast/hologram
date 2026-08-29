defmodule HologramFeatureTests.ActionWritesTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [update: 3]

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.ActionWritesPage
  alias HologramFeatureTests.Entities.Todo

  # Todo references nothing, so it truncates alone - no other table's foreign keys reach it.
  setup do
    await_evaluator_drain()

    table = ~s("hologram_data"."#{Mapper.table_name(Todo)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    :ok
  end

  # Polls the SERVER until it holds what the batch should have put there. The row arriving is the
  # confirmation - 09a exposes no per-row durability to assert on instead.
  defp await_server_todos(expected_count) do
    Enum.reduce_while(1..100, [], fn _attempt, _acc ->
      todos = Enum.sort_by(DB.read(Todo), & &1.title)

      if length(todos) == expected_count do
        {:halt, todos}
      else
        Process.sleep(50)
        {:cont, todos}
      end
    end)
  end

  # Polls the SERVER until the one row holds the given number of votes.
  #
  # What it is for: while a batch's answer is held, nothing on the client says whether the server
  # has applied it. Knowing that it HAS is the starting point for making a later write whose
  # arrival proves the earlier one's frame has already been applied.
  defp await_server_votes(expected_votes) do
    Enum.reduce_while(1..100, nil, fn _attempt, _acc ->
      case DB.read(Todo) do
        [%Todo{votes: ^expected_votes} = todo] ->
          {:halt, todo}

        _not_yet ->
          Process.sleep(50)
          {:cont, nil}
      end
    end)
  end

  # Polls the queue's own window for the refusal, which is the deterministic point at which the
  # rollback has happened - asserting "the row appeared and then vanished" would race the round
  # trip in whichever direction the machine happened to be faster.
  defp await_rejected(session) do
    Enum.reduce_while(1..100, [], fn _attempt, _acc ->
      rejected =
        script_result(session, "return globalThis.Hologram.writes.rejected();")

      if rejected == [] do
        Process.sleep(50)
        {:cont, rejected}
      else
        {:halt, rejected}
      end
    end)
  end

  # Proves the DOM changed without the page being fetched again - a reload would take this marker
  # with it, so a passing assertion after one would say nothing.
  defp mark_this_page_load(session) do
    execute_script(session, "globalThis.__thisPageLoad = 'held';")
  end

  defp assert_same_page_load(session) do
    assert_script_result(session, "return globalThis.__thisPageLoad;", "held")
  end

  defp page_replica_id(session) do
    script_result(session, "return globalThis.Hologram.replicaId;")
  end

  # What the server kept of this browser's batches, scoped to the browser that sent them.
  defp record_rows(replica_id) do
    statement = """
    SELECT "result", "seq" FROM "hologram_system"."mutation"
    WHERE "replica_id" = $1 ORDER BY "seq"
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [replica_id])

    Enum.map(rows, fn [result, seq] -> %{result: result, seq: seq} end)
  end

  feature "writes a row into the list before it is sent, and the server receives it", %{
    session: session
  } do
    session =
      session
      |> visit(ActionWritesPage)
      |> mark_this_page_load()

    session
    |> click(button("Add one todo"))
    |> assert_text(css("#result"), "created_alpha")
    |> assert_text(css("#todos"), "alpha 0")
    |> assert_same_page_load()

    assert [%Todo{title: "alpha", done: false, votes: 0}] = await_server_todos(1)
  end

  feature "ships the writes of one action as a single batch", %{session: session} do
    session = visit(session, ActionWritesPage)

    session
    |> click(button("Add two todos"))
    |> assert_text(css("#result"), "created_two")

    assert [%Todo{title: "alpha"}, %Todo{title: "beta"}] = await_server_todos(2)

    assert [%{seq: 1}] = record_rows(page_replica_id(session))
  end

  feature "reads its own write inside the action that made it", %{session: session} do
    session
    |> visit(ActionWritesPage)
    |> click(button("Read own write"))
    |> assert_text(css("#result"), "read_alpha")

    assert [%Todo{title: "alpha"}] = await_server_todos(1)
  end

  feature "refuses a value the declarations reject without sending anything", %{session: session} do
    session = visit(session, ActionWritesPage)

    session
    |> click(button("Refuse an empty title"))
    |> assert_text(css("#result"), "refused_min_length_1")

    assert DB.read(Todo) == []
    assert record_rows(page_replica_id(session)) == []
  end

  feature "puts a value and moves a counter", %{session: session} do
    session = visit(session, ActionWritesPage)

    session
    |> click(button("Add one todo"))
    |> assert_text(css("#todos"), "alpha 0")
    |> click(button("Vote"))
    |> assert_text(css("#result"), "voted_1")
    |> click(button("Rename the todo"))
    |> assert_text(css("#result"), "renamed_beta")
    |> assert_text(css("#todos"), "beta 1")

    assert [%Todo{title: "beta", votes: 1}] = await_server_todos(1)
  end

  feature "deletes a row", %{session: session} do
    session = visit(session, ActionWritesPage)

    session
    |> click(button("Add one todo"))
    |> assert_text(css("#todos"), "alpha 0")

    assert [%Todo{title: "alpha"}] = await_server_todos(1)

    session
    |> click(button("Delete the todo"))
    |> assert_text(css("#result"), "deleted")
    |> refute_has(css("#todos li"))

    assert await_server_todos(0) == []
  end

  feature "discards the writes of an action that raises", %{session: session} do
    session = visit(session, ActionWritesPage)

    assert_js_error(session, "boom", fn ->
      click(session, button("Raise after adding"))
    end)

    refute_has(session, css("#todos li"))

    assert DB.read(Todo) == []
    assert record_rows(page_replica_id(session)) == []
  end

  feature "rolls a refused batch back and keeps what the server said", %{session: session} do
    %{slug: "taken", title: "seeded"}
    |> Todo.new()
    |> DB.create!()

    session =
      session
      |> visit(ActionWritesPage)
      |> assert_text(css("#todos"), "seeded 0")

    session
    |> click(button("Add a todo with a taken slug"))
    |> assert_text(css("#result"), "created_dup")

    assert [%{"seq" => 1, "write" => 0}] = await_rejected(session)

    refute_text(session, css("#todos"), "dup")

    assert [%Todo{title: "seeded"}] = DB.read(Todo)
  end

  # A write made elsewhere reaches the row while this browser holds an unsent write of its own.
  # The two name different columns, so both stand - the frame writes the base underneath and the
  # pending write folds over it, neither taking the other's column.
  #
  # Both writes here set a VALUE, which is what makes this the stable case: applying a value twice
  # leaves what applying it once leaves, so nothing about the outcome depends on whether the
  # answer or the frame arrives first. A moved counter is the case where that stops being true,
  # and it is the next test.
  feature "keeps a pending write on top of a row the server changed meanwhile", %{
    session: session
  } do
    session =
      session
      |> visit(ActionWritesPage)
      |> click(button("Add one todo"))
      |> assert_text(css("#todos"), "alpha 0")

    [%Todo{id: todo_id}] = await_server_todos(1)

    session
    |> hold_mutation_requests()
    |> click(button("Rename the todo"))
    |> assert_text(css("#result"), "renamed_beta")
    |> assert_text(css("#todos"), "beta 0")

    :ok = update(Todo, todo_id, %{votes: 5})

    session
    |> assert_text(css("#todos"), "beta 5")
    |> release_mutations()
    |> await_pending_writes(0)
    |> assert_text(css("#todos"), "beta 5")

    assert [%Todo{title: "beta", votes: 5}] = await_server_todos(1)
  end

  # One write reaches this browser twice: as the answer to the request that made it, and as a
  # frame on the stream. Nothing orders the two, and when the frame wins the base already holds
  # the move - so folding the pending move on top again shows one more than the server has, and
  # promoting it afterwards writes that number down for good, with no later frame to correct it.
  #
  # Holding the ANSWER is what puts the frame first on purpose. The foreign rename that follows is
  # the clock: it is written only once the server holds the vote, and frames arrive in order, so
  # the renamed title showing means the vote's own frame has already been applied underneath.
  feature "counts a moved counter once when its frame lands before its answer", %{
    session: session
  } do
    session =
      session
      |> visit(ActionWritesPage)
      |> click(button("Add one todo"))
      |> assert_text(css("#todos"), "alpha 0")

    [%Todo{id: todo_id}] = await_server_todos(1)

    session
    |> hold_mutation_answers()
    |> click(button("Vote"))
    |> assert_text(css("#result"), "voted_1")
    |> assert_text(css("#todos"), "alpha 1")

    await_server_votes(1)

    :ok = update(Todo, todo_id, %{title: "beta"})

    session
    |> assert_text(css("#todos"), "beta 1")
    |> release_mutations()
    |> await_pending_writes(0)
    |> assert_text(css("#todos"), "beta 1")

    assert [%Todo{title: "beta", votes: 1}] = await_server_todos(1)
  end

  # A newer edit from elsewhere reaches the SAME column this browser holds an unsent write to. The
  # server will rule for the newer edit, and the browser can tell that from the row it already
  # has: the arriving value carries a revision above the pending write's stamp, which is the very
  # comparison the server's merge makes. So the winner shows as soon as its frame lands, rather
  # than after the round trip, and the pending value is never put back on top of it.
  #
  # A column that loses is not a refusal - the batch is confirmed and the lost value is named on
  # the answer - so nothing reaches the rejected queue.
  feature "shows a newer edit from elsewhere through a pending one", %{session: session} do
    session =
      session
      |> visit(ActionWritesPage)
      |> click(button("Add one todo"))
      |> assert_text(css("#todos"), "alpha 0")

    [%Todo{id: todo_id}] = await_server_todos(1)

    session
    |> hold_mutation_requests()
    |> click(button("Rename the todo"))
    |> assert_text(css("#result"), "renamed_beta")
    |> assert_text(css("#todos"), "beta 0")

    :ok = update(Todo, todo_id, %{title: "gamma"})

    session
    |> assert_text(css("#todos"), "gamma 0")
    |> release_mutations()
    |> await_pending_writes(0)
    |> assert_text(css("#todos"), "gamma 0")

    assert script_result(session, "return globalThis.Hologram.writes.rejected();") == []

    assert [%Todo{title: "gamma"}] = await_server_todos(1)
  end

  # A delete is judged like any other write: it takes the row only when nothing has moved past the
  # stamp it was made at. A newer edit from elsewhere is such a move, so the server keeps the row -
  # and the browser, already holding the arriving revision, can tell that before the answer comes
  # back. The row the user deleted reappears, which is the server's ruling shown early rather than
  # a write being undone.
  #
  # The failure this pins is the worst of the three, because it outlives the round trip: a delete
  # that loses but is promoted anyway takes the row out of the base, and a later patch for a row
  # the client no longer holds is passed over - so nothing ever puts it back.
  feature "keeps a row whose delete lost to a newer edit", %{session: session} do
    session =
      session
      |> visit(ActionWritesPage)
      |> click(button("Add one todo"))
      |> assert_text(css("#todos"), "alpha 0")

    [%Todo{id: todo_id}] = await_server_todos(1)

    session
    |> hold_mutation_requests()
    |> click(button("Delete the todo"))
    |> assert_text(css("#result"), "deleted")
    |> refute_has(css("#todos li"))

    :ok = update(Todo, todo_id, %{title: "gamma"})

    session
    |> assert_text(css("#todos"), "gamma 0")
    |> release_mutations()
    |> await_pending_writes(0)
    |> assert_text(css("#todos"), "gamma 0")

    assert [%Todo{title: "gamma"}] = await_server_todos(1)
  end
end
