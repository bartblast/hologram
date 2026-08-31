defmodule HologramFeatureTests.TimeAttributeTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false
  use Hologram.DB

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Shop
  alias HologramFeatureTests.TimeAttributePage

  # Shop references nothing, so it truncates alone - no other table's foreign keys reach it.
  setup do
    await_evaluator_drain()

    table = ~s("hologram_data"."#{Mapper.table_name(Shop)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    :ok
  end

  # Polls the SERVER until it holds the given number of shops, in the order IT puts them in -
  # the same claim the page makes, asked of the other tier.
  defp await_server_shops(expected_count) do
    Enum.reduce_while(1..100, [], fn _attempt, _acc ->
      shops =
        Shop
        |> order_by(:opens_at)
        |> DB.read()

      if length(shops) == expected_count do
        {:halt, shops}
      else
        Process.sleep(50)
        {:cont, shops}
      end
    end)
  end

  defp assert_same_page_load(session) do
    assert_script_result(session, "return globalThis.__thisPageLoad;", "held")
  end

  # Proves the DOM changed without the page being fetched again - a reload would take this marker
  # with it, so a passing assertion after one would say nothing.
  defp mark_this_page_load(session) do
    execute_script(session, "globalThis.__thisPageLoad = 'held';")
  end

  defp page_replica_id(session) do
    script_result(session, "return globalThis.Hologram.replicaId;")
  end

  # The times on screen are the client's own boxing read by a template, and they are spelled at
  # full precision - the same spelling the server writes, which is what lets the two tiers compare
  # the value as the plain string it travels as.
  feature "renders the times the browser wrote, in time order, before anything is sent", %{
    session: session
  } do
    session =
      session
      |> visit(TimeAttributePage)
      |> mark_this_page_load()

    session
    |> click(button("Add two shops at different times"))
    |> assert_text(css("#result"), "created_two")
    |> assert_text(css("#shop_order"), "dawn,noon")
    |> assert_text(css("#shops"), "dawn 08:30:00.000000 16:30:00.000000")
    |> assert_text(css("#shops"), "noon 12:00:00.000000 20:00:00.000000")
    |> assert_same_page_load()

    assert [
             %Shop{name: "dawn", closes_at: ~T[16:30:00.000000], opens_at: ~T[08:30:00.000000]},
             %Shop{name: "noon", closes_at: ~T[20:00:00.000000], opens_at: ~T[12:00:00.000000]}
           ] = await_server_shops(2)
  end

  # Where a row with no time lands is a question both tiers answer, and they have to answer it the
  # same way: the order on screen is the client kernel's, the order below is Postgres's.
  feature "sorts a shop with no opening hour after the ones that have one", %{session: session} do
    session = visit(session, TimeAttributePage)

    session
    |> click(button("Add two shops at different times"))
    |> assert_text(css("#shop_order"), "dawn,noon")
    |> click(button("Add a shop with no hours"))
    |> assert_text(css("#result"), "created_anytime")
    |> assert_text(css("#shop_order"), "dawn,noon,anytime")

    assert [
             %Shop{name: "dawn"},
             %Shop{name: "noon"},
             %Shop{name: "anytime", closes_at: nil, opens_at: nil}
           ] = await_server_shops(3)
  end

  # The declarations are baked into the bundle, so the browser judges this one on its own - and it
  # can only do that by comparing two times, which nothing transpiled does. What compares them is
  # the hand-written half of Hologram.Entity, and this is the only thing that exercises it.
  feature "refuses a time outside the declared bounds without sending anything", %{
    session: session
  } do
    session = visit(session, TimeAttributePage)

    session
    |> click(button("Refuse a shop opening too late"))
    |> assert_text(css("#result"), "refused_max_20")

    assert DB.read(Shop) == []
    assert mutation_record_rows(page_replica_id(session)) == []
  end
end
