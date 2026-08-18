defmodule HologramFeatureTests.LocalDatabaseTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1, delete: 2, update: 3]

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Queries.Page2

  # The inversion the sync tests were waiting for: those assert what the SERVER says on the wire,
  # and these assert what the CLIENT does with it. Nothing here dispatches an action or reloads -
  # a row moves in Postgres, and the DOM that read it through a from_query prop follows, because
  # the prop re-resolves against the client's own database on every render the stream schedules.
  setup do
    await_evaluator_drain()

    statement = ~s(TRUNCATE "hologram_data"."#{Mapper.table_name(Product)}")
    {:ok, _result} = Connection.query(statement, [])

    :ok
  end

  # Proves the DOM changed without the page being fetched again: a reload would take this marker
  # with it, so a passing assertion after one would say nothing.
  defp mark_this_page_load(session) do
    execute_script(session, "globalThis.__thisPageLoad = 'held';")
  end

  defp assert_same_page_load(session) do
    assert_script_result(session, "return globalThis.__thisPageLoad;", "held")
  end

  feature "shows a value changed after the page was rendered", %{session: session} do
    product =
      Product
      |> Entity.new(name: "abacus")
      |> create()

    session
    |> visit(Page2)
    |> assert_text(css("#live_products"), "abacus")
    |> mark_this_page_load()

    update(Product, product.id, name: "armchair")

    session
    |> assert_text(css("#live_products"), "armchair")
    |> assert_same_page_load()
  end

  feature "shows a row created after the page was rendered", %{session: session} do
    Product
    |> Entity.new(name: "bicycle")
    |> create()

    session
    |> visit(Page2)
    |> assert_text(css("#live_products"), "bicycle")
    |> mark_this_page_load()

    Product
    |> Entity.new(name: "birdcage")
    |> create()

    session
    |> assert_text(css("#live_products"), "bicycle,birdcage")
    |> assert_same_page_load()
  end

  feature "drops a row deleted after the page was rendered", %{session: session} do
    kept =
      Product
      |> Entity.new(name: "cabinet")
      |> create()

    removed =
      Product
      |> Entity.new(name: "candle")
      |> create()

    session
    |> visit(Page2)
    |> assert_text(css("#live_products"), "cabinet,candle")
    |> mark_this_page_load()

    delete(Product, removed.id)

    session
    |> assert_text(css("#live_products"), "cabinet")
    |> assert_same_page_load()

    # The row that stayed is still the row it was - an unsync takes one row out of the pot, not
    # whatever else the same query was reading.
    assert kept.name == "cabinet"
  end

  # The order is the query's, not the arrival order: a row landing on the stream is filed and
  # then read back through the same ordering the term declares.
  feature "places a row arriving later where the query orders it", %{session: session} do
    Product
    |> Entity.new(name: "dolphin")
    |> create()

    Product
    |> Entity.new(name: "dragon")
    |> create()

    session
    |> visit(Page2)
    |> assert_text(css("#live_products"), "dolphin,dragon")
    |> mark_this_page_load()

    Product
    |> Entity.new(name: "daffodil")
    |> create()

    session
    |> assert_text(css("#live_products"), "daffodil,dolphin,dragon")
    |> assert_same_page_load()
  end
end
