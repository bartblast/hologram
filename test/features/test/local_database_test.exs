defmodule HologramFeatureTests.LocalDatabaseTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [delete: 2, update: 3]

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Entities.Ticket
  alias HologramFeatureTests.Queries.Page2

  # The inversion the sync tests were waiting for: those assert what the SERVER says on the wire,
  # and these assert what the CLIENT does with it. Nothing here dispatches an action or reloads -
  # a row moves in Postgres, and the DOM that read it through a from_query prop follows, because
  # the prop re-resolves against the client's own database on every render the stream schedules.

  # Both tables truncate in one statement: the review table's foreign key to the product table
  # makes Postgres reject truncating the referenced table alone.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join([Product, Review, Ticket], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

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
      %{name: "abacus"}
      |> Product.new()
      |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(css("#live_products"), ~r/^abacus$/)
    |> mark_this_page_load()

    update(Product, product.id, name: "armchair")

    session
    |> assert_text(css("#live_products"), ~r/^armchair$/)
    |> assert_same_page_load()
  end

  feature "shows a row created after the page was rendered", %{session: session} do
    %{name: "bicycle"}
    |> Product.new()
    |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(css("#live_products"), ~r/^bicycle$/)
    |> mark_this_page_load()

    %{name: "birdcage"}
    |> Product.new()
    |> DB.create!()

    session
    |> assert_text(css("#live_products"), ~r/^bicycle,birdcage$/)
    |> assert_same_page_load()
  end

  feature "drops a row deleted after the page was rendered", %{session: session} do
    kept =
      %{name: "cabinet"}
      |> Product.new()
      |> DB.create!()

    removed =
      %{name: "candle"}
      |> Product.new()
      |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(css("#live_products"), ~r/^cabinet,candle$/)
    |> mark_this_page_load()

    delete(Product, removed.id)

    session
    |> assert_text(css("#live_products"), ~r/^cabinet$/)
    |> assert_same_page_load()

    # The row that stayed is still the row it was - an unsync takes one row out of the pot, not
    # whatever else the same query was reading.
    assert kept.name == "cabinet"
  end

  # The order is the query's, not the arrival order: a row landing on the stream is filed and
  # then read back through the same ordering the term declares.
  feature "places a row arriving later where the query orders it", %{session: session} do
    %{name: "dolphin"}
    |> Product.new()
    |> DB.create!()

    %{name: "dragon"}
    |> Product.new()
    |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(css("#live_products"), ~r/^dolphin,dragon$/)
    |> mark_this_page_load()

    %{name: "daffodil"}
    |> Product.new()
    |> DB.create!()

    session
    |> assert_text(css("#live_products"), ~r/^daffodil,dolphin,dragon$/)
    |> assert_same_page_load()
  end

  # The first paint is the server's, out of Postgres, and what is read here is after hydration,
  # out of the client's own database - so one assertion covers both executors agreeing.
  feature "orders rows by an enum in its declared order", %{session: session} do
    %{priority: :medium, title: "a"}
    |> Ticket.new()
    |> DB.create!()

    %{priority: :high, title: "b"}
    |> Ticket.new()
    |> DB.create!()

    %{priority: :low, title: "c"}
    |> Ticket.new()
    |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(css("#tickets"), ~r/^c,a,b$/)
  end

  feature "filters rows at or above a declared enum value", %{session: session} do
    %{priority: :low, title: "a"}
    |> Ticket.new()
    |> DB.create!()

    %{priority: :medium, title: "b"}
    |> Ticket.new()
    |> DB.create!()

    %{priority: :high, title: "c"}
    |> Ticket.new()
    |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(css("#urgent_tickets"), ~r/^b,c$/)
  end

  # Two rows, and their priorities stay pairwise distinct across the update - so the order is
  # decided by the enum alone. A third row would force two of them onto one value, and the
  # implicit id tiebreaker cannot settle that: an id's sub-millisecond bits are random, so rows
  # created in the same millisecond order unpredictably.
  feature "re-files a row whose enum value changed", %{session: session} do
    ticket_a =
      %{priority: :low, title: "a"}
      |> Ticket.new()
      |> DB.create!()

    %{priority: :medium, title: "b"}
    |> Ticket.new()
    |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(css("#tickets"), ~r/^a,b$/)
    |> mark_this_page_load()

    update(Ticket, ticket_a.id, priority: :high)

    session
    |> assert_text(css("#tickets"), ~r/^b,a$/)
    |> assert_same_page_load()
  end

  # The first paint is the server's and what is read afterwards is the hydrated client's, so one
  # assertion covers both executors: "Łódź" and "apple" fold below the bound, the rest at or above
  # it, and the order they come back in is the order the bound was placed against.
  feature "filters rows by a string bound in the order they sort", %{session: session} do
    Enum.each(["apple", "Łódź", "Mango", "Ödön", "Zebra"], fn name ->
      %{name: name}
      |> Product.new()
      |> DB.create!()
    end)

    session
    |> visit(Page2)
    |> assert_text(css("#products_from_m"), ~r/^Mango,Ödön,Zebra$/)
  end

  feature "re-files a row whose value crosses a string bound", %{session: session} do
    apple =
      %{name: "apple"}
      |> Product.new()
      |> DB.create!()

    %{name: "Mango"}
    |> Product.new()
    |> DB.create!()

    %{name: "Zebra"}
    |> Product.new()
    |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(css("#products_from_m"), ~r/^Mango,Zebra$/)
    |> mark_this_page_load()

    update(Product, apple.id, name: "mulberry")

    session
    |> assert_text(css("#products_from_m"), ~r/^Mango,mulberry,Zebra$/)
    |> assert_same_page_load()
  end

  # A revision is framework state under __meta__ rather than an attribute, so these two cover a
  # path nothing else here does: the server's struct fills the first paint, and the stream fills
  # it again from the revisions a patch carries for the columns it names.
  feature "shows the revision a row's name was set at", %{session: session} do
    product =
      %{name: "abacus"}
      |> Product.new()
      |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(
      css("#product_revisions"),
      ~r/^abacus:#{product.__meta__.revisions.name}$/
    )
  end

  feature "moves the revision of a name changed after the page was rendered",
          %{session: session} do
    product =
      %{name: "abacus"}
      |> Product.new()
      |> DB.create!()

    session
    |> visit(Page2)
    |> assert_text(
      css("#product_revisions"),
      ~r/^abacus:#{product.__meta__.revisions.name}$/
    )
    |> mark_this_page_load()

    update(Product, product.id, name: "armchair")

    reloaded = DB.read(Product, product.id)

    session
    |> assert_text(
      css("#product_revisions"),
      ~r/^armchair:#{reloaded.__meta__.revisions.name}$/
    )
    |> assert_same_page_load()
  end
end
