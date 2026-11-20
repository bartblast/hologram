defmodule HologramFeatureTests.CreatedRowsTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Locker
  alias HologramFeatureTests.Entities.Slip
  alias HologramFeatureTests.Policies.Page13

  # The browser creates rows it shows at once, and keeps them once the server confirms their batch,
  # until the page reloads. Rows its user may not read leave it then, so its local queries don't
  # list them and its rules don't read them. A reload isn't checked: the browser never writes a
  # confirmed batch's rows to disk, so a reload drops them with or without the server's word.
  setup do
    await_evaluator_drain()

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
end
