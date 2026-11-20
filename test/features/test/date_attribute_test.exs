defmodule HologramFeatureTests.DateAttributeTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false
  use Hologram.DB

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.DateAttributePage
  alias HologramFeatureTests.Entities.Event

  # Event references nothing, so it truncates alone - no other table's foreign keys reach it.
  setup do
    table = ~s("hologram_data"."#{Mapper.table_name(Event)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    :ok
  end

  # Polls the SERVER until it holds the given number of events, in the order it sorts them by.
  defp await_server_events(expected_count, order_by) do
    Enum.reduce_while(1..100, [], fn _attempt, _acc ->
      events =
        order_by
        |> server_query()
        |> DB.read()

      if length(events) == expected_count do
        {:halt, events}
      else
        Process.sleep(50)
        {:cont, events}
      end
    end)
  end

  defp server_query(:held_on), do: sort(Event, held_on)

  defp server_query(:starts_at), do: sort(Event, starts_at)

  defp create_event!(attrs) do
    attrs
    |> Event.new()
    |> DB.create!()
  end

  # The page filters by midnight in Warsaw, which is 23:00 UTC the day before - so an event at
  # 23:30 UTC is after it. The browser's mount render answers the query over the rows the page
  # carried, so the event is listed only if the browser takes the bound for the instant it stands
  # for. The write adds a row of the browser's own, which it orders after the carried one.
  feature "lists an event after a zoned instant the way the server does", %{session: session} do
    create_event!(%{name: "late_feb", starts_at: ~U[2026-02-28 23:30:00Z]})

    session
    |> visit(DateAttributePage)
    |> assert_text(css("#event_order"), ~r/^late_feb$/)
    |> click(button("Add an event in March"))
    |> assert_text(css("#result"), "created_march")
    |> assert_text(css("#event_order"), ~r/^late_feb,march$/)
  end

  # A write carries the instant the struct stands for, whatever its zone - the same instant the
  # page filters from, so the browser lists the event it wrote too.
  feature "stores the instant a zoned datetime the browser wrote stands for", %{session: session} do
    session
    |> visit(DateAttributePage)
    |> click(button("Add an event at midnight in Warsaw"))
    |> assert_text(css("#result"), "created_warsaw")
    |> assert_text(css("#event_order"), ~r/^warsaw$/)

    assert [%Event{name: "warsaw", starts_at: starts_at}] = await_server_events(1, :starts_at)
    assert starts_at == ~U[2026-02-28 23:00:00.000000Z]
  end

  # The order on screen is the browser's own, the order below is Postgres's, and the days are
  # written out of order - so they agree only if the browser orders years below 0 and past 9999
  # by the day, and writes and reads them as the server spells them.
  feature "orders days below year 0 and past 9999 the way the server does", %{session: session} do
    session
    |> visit(DateAttributePage)
    |> click(button("Add four days across the eras"))
    |> assert_text(css("#result"), "created_days")
    |> assert_text(css("#day_order"), ~r/^-0002-01-01,-0001-01-01,9999-12-31,10000-01-01$/)

    assert [
             %Event{held_on: ~D[-0002-01-01]},
             %Event{held_on: ~D[-0001-01-01]},
             %Event{held_on: ~D[9999-12-31]},
             %Event{held_on: last_day}
           ] = await_server_events(4, :held_on)

    assert last_day == Date.new!(10_000, 1, 1)
  end

  # The browser's mount render reads the stored day off the rows the page carried, and the day the
  # browser adds itself has to land in front of it.
  feature "reads a day past year 9999 the server stored", %{session: session} do
    create_event!(%{held_on: Date.new!(20_250, 1, 1), name: "far"})

    session
    |> visit(DateAttributePage)
    |> assert_text(css("#day_order"), ~r/^20250-01-01$/)
    |> click(button("Add the last day of 9999"))
    |> assert_text(css("#result"), "created_last_day")
    |> assert_text(css("#day_order"), ~r/^9999-12-31,20250-01-01$/)
  end
end
