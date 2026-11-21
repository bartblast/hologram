defmodule HologramFeatureTests.CreatedRowsTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Locker
  alias HologramFeatureTests.Entities.Slip
  alias HologramFeatureTests.Policies.Page13

  @all_marker ~s|event.type === "synced" && JSON.parse(event.data).scope === "all"|

  # The browser creates rows it shows at once, and keeps them once the server confirms their batch,
  # until the page reloads. Rows its user may not read leave it then, so its local queries don't
  # list them and its rules don't read them. A reload after the batch is confirmed isn't checked:
  # the browser writes a confirmed batch's row its user may not read to disk only when a tab taking
  # the lead finds the store out of step with it, so a reload almost always drops the row even
  # before the fix.
  setup do
    {:ok, _result} =
      Connection.query(
        ~s(TRUNCATE "hologram_data"."#{Mapper.table_name(Locker)}", "hologram_data"."#{Mapper.table_name(Slip)}"),
        []
      )

    :ok
  end

  # The browser shows the locker before its batch reaches the server, so the test waits for the
  # server to hold it.
  defp await_server_locker do
    await_server_locker(100)
  end

  defp await_server_locker(0) do
    raise Wallaby.ExpectationNotMetError, "Timed out waiting for the server to hold the locker"
  end

  defp await_server_locker(attempts_left) do
    case DB.read(Locker) do
      [locker] ->
        locker

      [] ->
        Process.sleep(50)
        await_server_locker(attempts_left - 1)
    end
  end

  defp await_server_slips(attempts_left \\ 100)

  defp await_server_slips(0) do
    raise Wallaby.ExpectationNotMetError, "Timed out waiting for the server to hold the slips"
  end

  defp await_server_slips(attempts_left) do
    if length(DB.read(Slip)) < 2 do
      Process.sleep(50)
      await_server_slips(attempts_left - 1)
    end
  end

  # Waits for the sync gate to hold a frame the given JavaScript condition on `event` picks.
  defp await_held(session, condition, attempts_left \\ 100)

  defp await_held(_session, condition, 0) do
    raise Wallaby.ExpectationNotMetError, "Timed out waiting for a held frame: #{condition}"
  end

  defp await_held(session, condition, attempts_left) do
    script = """
    return globalThis.__hologramSyncGate.parked.some(([_listener, event]) => #{condition});
    """

    if script_result(session, script) do
      session
    else
      Process.sleep(50)
      await_held(session, condition, attempts_left - 1)
    end
  end

  defp create_closed_locker do
    %{open: false}
    |> Locker.new()
    |> DB.create!()
  end

  # An action's render reads the rows as they stand, so what's on screen after it holds everything
  # the browser was told before the click. An answer only schedules a render.
  defp render_now(session) do
    session
    |> click(button("Check new slip"))
    |> assert_text(css("#new_slip"), ~r/^false$/)
  end

  # Leaves the browser holding a whole fill it hasn't applied, with the rows of its "Create slips"
  # batch on the server and the batch's answer held.
  #
  # The session serving the browser when the batch commits would tell it to drop the row it may not
  # read, so that session's frames are held and thrown away. Emptying the log then makes the browser
  # start over when it reconnects, so no session ever judges the batch again. Each locker gives the
  # log an effect older than the next place: an empty log would make the first reconnect start over
  # too, and a reload after the new fill as well. Starting over takes a second connection, whose
  # greeting marks what the browser holds, so the wait is for the new fill: an answer landing before
  # that greeting is one the fill's markers already sweep.
  defp start_fill_with_answer_held(session) do
    create_closed_locker()

    filled =
      session
      |> visit_page()
      |> hold_sync_frames()

    instance_id = current_instance_id(filled)

    simulate_sse_disconnect(instance_id)

    clicked =
      filled
      |> await_held(@all_marker)
      |> hold_sync_frames()
      |> hold_mutation_answers()
      |> click(button("Create slips"))

    await_server_slips()
    await_held(clicked, ~s(event.type === "sync_deltas"))

    truncate_oplog()
    create_closed_locker()

    rearmed = hold_sync_frames(clicked)

    simulate_sse_disconnect(instance_id)

    await_held(rearmed, @all_marker)
  end

  defp visit_page(session) do
    session
    |> visit(Page13)
    |> await_local_fill()
  end

  feature "drops a row the browser created once the server confirms its user may not read it",
          %{session: session} do
    session
    |> visit_page()
    |> click(button("Create slips"))
    |> assert_text(css("#slips"), ~r/^shared$/)
  end

  feature "drops a created row of a type with no read line", %{session: session} do
    session
    |> visit_page()
    |> click(button("Create locker"))
    |> assert_text(css("#slips"), ~r/^boxed$/)
    |> assert_text(css("#lockers"), ~r/^0$/)
  end

  # The server closes the locker after the browser's batch, so a rule the browser answered from its
  # own copy of the locker would say yes. Once the browser drops the locker, it has nothing to
  # answer the rule from, and a new slip carries no answer from the server, so it says no.
  feature "doesn't answer a rule from a created row the server dropped", %{session: session} do
    session =
      session
      |> visit_page()
      |> click(button("Create locker"))
      |> assert_text(css("#slips"), ~r/^boxed$/)

    DB.update!(Locker, await_server_locker().id, open: false)

    session
    |> assert_text(css("#slips"), ~r/^$/)
    |> click(button("Check new slip"))
    |> assert_text(css("#new_slip"), ~r/^false$/)
  end

  feature "drops a created row whose answer arrives after the fill that left it out",
          %{session: session} do
    session
    |> start_fill_with_answer_held()
    |> release_sync_frames()
    |> await_local_fill()
    |> release_mutations()
    |> await_pending_writes(0)
    |> render_now()
    |> assert_text(css("#slips"), ~r/^shared$/)
  end

  feature "drops a created row whose answer arrives before the fill that leaves it out",
          %{session: session} do
    session
    |> start_fill_with_answer_held()
    |> release_mutations()
    |> await_pending_writes(0)
    |> render_now()
    |> assert_text(css("#slips"), ~r/orphan/)
    |> release_sync_frames()
    |> await_local_fill()
    |> assert_text(css("#slips"), ~r/^shared$/)
  end

  # The page load that sends the batch again hears no type's marker, since it comes back with a
  # place. Holding the place is also what says it has taken the batch up from the store.
  feature "doesn't file a created row the fill left out when a reload sends its batch again",
          %{session: session} do
    session
    |> start_fill_with_answer_held()
    |> release_sync_frames()
    |> await_local_fill()
    |> await_durable_writes()
    |> visit(Page13)
    |> await_local_fill()
    |> await_pending_writes(0)
    |> render_now()
    |> assert_text(css("#slips"), ~r/^shared$/)
  end
end
