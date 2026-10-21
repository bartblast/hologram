defmodule HologramFeatureTests.QueriesTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Booking
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Entities.Ticket
  alias HologramFeatureTests.Queries.Page1
  alias HologramFeatureTests.Queries.Page3
  alias HologramFeatureTests.Queries.Page4
  alias HologramFeatureTests.Queries.Page5
  alias HologramFeatureTests.Queries.Page6

  @place_script "return globalThis.Hologram.durability.cursor();"

  # The client's local database is filled by evaluators that outlive a test, and a TRUNCATE never
  # reaches the operations log they read, so they drain before the tables empty. The tables
  # truncate in one statement: the review table's foreign key to the product table makes Postgres
  # reject truncating the referenced table alone.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join([Booking, Product, Review, Ticket], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  feature "renders a query filtering on a field of an entity prop", %{session: session} do
    seed_products_and_reviews()

    session
    |> visit(Page3)
    |> assert_text(css("#field_read"), "aa,bb")
  end

  feature "renders a page whose parent query matched nothing", %{session: session} do
    session
    |> visit(Page3)
    |> assert_has(css("#dynamic_order"))
    |> refute_has(css("#field_read"))
  end

  feature "renders a query whose entity type is a prop", %{session: session} do
    seed_products_and_reviews()

    session
    |> visit(Page3)
    |> assert_text(css("#dynamic_entity"), "bb")
  end

  feature "renders a query whose ordering key is a prop", %{session: session} do
    seed_products_and_reviews()

    session
    |> visit(Page3)
    |> assert_text(css("#dynamic_order"), "aa,cc,bb")
  end

  # The ordering key arrives as a prop, so the build cannot know which attribute it names - what
  # puts these rows in practical order is the key every string attribute carries, not a companion
  # registered for this query.
  feature "orders rows by a dynamic string key in practical order", %{session: session} do
    product =
      %{name: "Widget"}
      |> Product.new()
      |> DB.create!()

    Enum.each(["Zebra", "apple", "Łódź"], fn body ->
      %{body: body, product_id: product.id, rating: 3}
      |> Review.new()
      |> DB.create!()
    end)

    session
    |> visit(Page3)
    |> assert_text(css("#dynamic_string_order"), ~r/^apple,Łódź,Zebra$/)
  end

  feature "renders from_query prop results in practical order", %{session: session} do
    %{name: "Zürich"}
    |> Product.new()
    |> DB.create!()

    %{name: "Łódź"}
    |> Product.new()
    |> DB.create!()

    %{name: "apple"}
    |> Product.new()
    |> DB.create!()

    session
    |> visit(Page1)
    |> assert_text(css("#products"), "apple,Łódź,Zürich")
  end

  # Priority descending, then title: high charlie, then medium bravo and echo, with delta skipped by
  # its pinned title, zz by the literal exclusion and low alpha by the pinned bound - two kept.
  feature "renders a filter written as an expression with pinned values", %{session: session} do
    seed_tickets()

    session
    |> visit(Page4)
    |> assert_text(css("#expression_filter"), ~r/^charlie,bravo$/)
  end

  # By title, two per page: alpha and bravo on the first, charlie and delta on the second.
  feature "renders pinned pagination over a pinned ordering", %{session: session} do
    seed_tickets()

    session
    |> visit(Page4)
    |> assert_text(css("#pinned_pagination"), ~r/^charlie,delta$/)
  end

  # Medium or higher except delta, by title. The read runs in the browser, over the rows the page's
  # queries synced, from conditions passed as data. zz is among them although component 11
  # excludes it: component 12's window has no filter, so every ticket is local once the fill lands,
  # which is what the click waits for - before it, the client holds only the rows the render
  # carried.
  feature "runs a filter built at runtime over local data", %{session: session} do
    seed_tickets()

    session
    |> visit(Page4)
    |> await_local_fill()
    |> click(button("Read locally"))
    |> assert_text(css("#runtime_filter"), ~r/^bravo,charlie,echo,zz$/)
  end

  # The high tickets but delta, skipped by its pinned title, and the low one, by title.
  feature "renders a filter with alternatives", %{session: session} do
    seed_tickets()

    session
    |> visit(Page5)
    |> assert_text(css("#alternatives_filter"), ~r/^alpha,charlie,zz$/)
  end

  # Alpha by the first alternative, and the high tickets but zz by the second - delta among them,
  # which the rendered list skips, so the answer can only have come from the local rows.
  feature "runs a filter with alternatives over local data", %{session: session} do
    seed_tickets()

    session
    |> visit(Page5)
    |> await_local_fill()
    |> click(button("Read alternatives locally"))
    |> assert_text(css("#local_alternatives"), ~r/^alpha,charlie,delta$/)
  end

  # The bookings checking out before they check in - bravo and delta. The browser renders the
  # list again from its own rows once they land, so the page the server sent is read as well: it
  # carries the answer the database gave.
  feature "renders a filter comparing two attributes", %{session: session} do
    seed_bookings()

    session
    |> visit(Page6)
    |> assert_text(css("#reversed_bookings"), ~r/^bravo,delta$/)

    %HTTPoison.Response{body: html} = HTTPoison.get!("http://localhost:4002/queries/6")

    assert html =~ ~r{<strong id="reversed_bookings"><code>bravo,delta</code></strong>}
  end

  # The bookings with as many guests as places or more - bravo over, charlie at capacity. The
  # comparison is one no rendered list makes, so the answer can only have come from the local rows.
  feature "runs a filter comparing two attributes over local data", %{session: session} do
    seed_bookings()

    session
    |> visit(Page6)
    |> await_local_fill()
    |> click(button("Read overbooked locally"))
    |> assert_text(css("#local_overbooked"), ~r/^bravo,charlie$/)
  end

  # The place the client greets a stream with is held once a fill has declared the local database
  # complete, so polling for it is how a test waits for a whole fill to have landed. Raising rather
  # than returning: the click it gates would otherwise read the rows the render carried.
  defp await_local_fill(session, attempts_left \\ 100)

  defp await_local_fill(session, 0) do
    raise Wallaby.ExpectationNotMetError,
          "Timed out waiting for the local database to fill, the client holds place " <>
            inspect(script_result(session, @place_script))
  end

  defp await_local_fill(session, attempts_left) do
    if script_result(session, @place_script) do
      session
    else
      Process.sleep(50)
      await_local_fill(session, attempts_left - 1)
    end
  end

  # Each booking answers the two comparisons differently: alpha is neither reversed nor overbooked,
  # bravo is both, charlie is at capacity on a same-day stay, delta is reversed with room to spare.
  defp seed_bookings do
    Enum.each(
      [
        {"alpha", ~D[2026-03-01], ~D[2026-03-05], 2, 4},
        {"bravo", ~D[2026-03-10], ~D[2026-03-08], 5, 4},
        {"charlie", ~D[2026-04-01], ~D[2026-04-01], 4, 4},
        {"delta", ~D[2026-05-02], ~D[2026-05-01], 1, 2}
      ],
      fn {name, check_in, check_out, guests, capacity} ->
        %{
          capacity: capacity,
          check_in: check_in,
          check_out: check_out,
          guests: guests,
          name: name
        }
        |> Booking.new()
        |> DB.create!()
      end
    )
  end

  # Two products so the parent's ordering picks a definite one to pass down, and reviews split
  # across both so a query filtering by the passed product reads fewer rows than one that does not.
  defp seed_products_and_reviews do
    alpha =
      %{name: "alpha"}
      |> Product.new()
      |> DB.create!()

    beta =
      %{name: "beta"}
      |> Product.new()
      |> DB.create!()

    %{body: "aa", product_id: alpha.id, rating: 2}
    |> Review.new()
    |> DB.create!()

    %{body: "bb", product_id: alpha.id, rating: 5}
    |> Review.new()
    |> DB.create!()

    %{body: "cc", product_id: beta.id, rating: 3}
    |> Review.new()
    |> DB.create!()

    :ok
  end

  # Distinct titles, so no ordering leans on the id tiebreaker.
  defp seed_tickets do
    Enum.each(
      [
        {"alpha", :low},
        {"bravo", :medium},
        {"charlie", :high},
        {"delta", :high},
        {"echo", :medium},
        {"zz", :high}
      ],
      fn {title, priority} ->
        %{priority: priority, title: title}
        |> Ticket.new()
        |> DB.create!()
      end
    )
  end
end
