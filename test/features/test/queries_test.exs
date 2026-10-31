defmodule HologramFeatureTests.QueriesTest do
  use HologramFeatureTests.TestCase, async: false

  import Hologram.Query, only: [add_relationship: 3, delete_relationship: 3]

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Booking
  alias HologramFeatureTests.Entities.Channel
  alias HologramFeatureTests.Entities.Label
  alias HologramFeatureTests.Entities.Leg
  alias HologramFeatureTests.Entities.Message
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Entities.Stop
  alias HologramFeatureTests.Entities.Ticket
  alias HologramFeatureTests.Entities.Topic
  alias HologramFeatureTests.Entities.Trip
  alias HologramFeatureTests.Queries.Page1
  alias HologramFeatureTests.Queries.Page3
  alias HologramFeatureTests.Queries.Page4
  alias HologramFeatureTests.Queries.Page5
  alias HologramFeatureTests.Queries.Page6
  alias HologramFeatureTests.Queries.Page7
  alias HologramFeatureTests.Queries.Page8

  # The client's local database is filled by evaluators that outlive a test, and a TRUNCATE never
  # reaches the operations log they read, so they drain before the tables empty. The tables
  # truncate in one statement: the foreign keys between them - a review's to its product, a
  # message's to its channel and the message labels' join table's to both its sides, among others -
  # make Postgres reject truncating a referenced table alone.
  setup do
    await_evaluator_drain()

    entity_tables =
      Enum.map(
        [Booking, Channel, Label, Leg, Message, Product, Review, Stop, Ticket, Topic, Trip],
        &Mapper.table_name/1
      )

    tables =
      entity_tables
      |> Enum.concat([DB.join_table_name(Message, :labels)])
      |> Enum.map_join(", ", &~s("hologram_data"."#{&1}"))

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

  # The stops whose trip is active - a1 and a2 on alpha, b1 on beta, and not g1 on the archived
  # gamma. The browser renders the list again from its own rows once they land, so the list is
  # read after the fill, on the same page load, and the page the server sent is read as well: it
  # carries the answer the database gave.
  feature "renders a filter through a to-one relationship", %{session: session} do
    seed_stops()

    session
    |> visit(Page7)
    |> mark_this_page_load()
    |> await_local_fill()
    |> assert_text(css("#active_stops"), ~r/^a1,a2,b1$/)
    |> assert_same_page_load()

    %HTTPoison.Response{body: html} = HTTPoison.get!("http://localhost:4002/queries/7")

    assert html =~ ~r{<strong id="active_stops"><code>a1,a2,b1</code></strong>}
  end

  # The stops on the trip named alpha. No rendered list compares a trip's name, so the answer can
  # only come from the local stops and the trips the query downloaded along its path.
  feature "runs a filter through a to-one relationship over local data", %{session: session} do
    seed_stops()

    session
    |> visit(Page7)
    |> await_local_fill()
    |> click(button("Read alpha stops locally"))
    |> assert_text(css("#local_alpha_stops"), ~r/^a1,a2$/)
  end

  # Archiving alpha changes no stop, and its stops still leave the list - the query reads the trip
  # through the path, so a change to the trip re-evaluates it, on the same page load.
  feature "re-evaluates a filter when a row along its path changes", %{session: session} do
    trips = seed_stops()

    session =
      session
      |> visit(Page7)
      |> assert_text(css("#active_stops"), ~r/^a1,a2,b1$/)
      |> mark_this_page_load()

    DB.update!(Trip, trips["alpha"].id, archived: true)

    session
    |> assert_text(css("#active_stops"), ~r/^b1$/)
    |> assert_same_page_load()
  end

  # The messages and the topic reach the client only through the inverses - no page roots one -
  # general's in position order. Once the page has mounted, what is on screen is the browser's own
  # render, answered from its database, on the same page load, and the page the server sent is read
  # as well.
  feature "renders inverse relationships", %{session: session} do
    seed_channels()

    session
    |> visit(Page8)
    |> mark_this_page_load()
    |> await_page_mount(Page8)
    |> assert_text(css("#channel_messages"), ~r/^general: hi, there \| topic: welcome$/)
    |> assert_text(css("#label_messages"), ~r/^urgent: hi, there$/)
    |> assert_same_page_load()

    %HTTPoison.Response{body: html} = HTTPoison.get!("http://localhost:4002/queries/8")

    assert html =~
             ~r{<strong id="channel_messages"><code>general: hi, there \| topic: welcome</code></strong>}

    assert html =~ ~r{<strong id="label_messages"><code>urgent: hi, there</code></strong>}
  end

  # Random's message and topic and later's messages, read through the inverses. The render reads
  # only general and urgent, so bye and off-topic can only have come with the stream's fill.
  feature "reads inverse relationships over local data", %{session: session} do
    seed_channels()

    session
    |> visit(Page8)
    |> await_local_fill()
    |> click(button("Read unrendered messages locally"))
    |> assert_text(css("#local_unrendered_messages"), ~r{^bye/off-topic; bye,hi$})

    # The page the server sent carries neither row, rendered or handed over beside the render - a
    # handed-over value is a JSON string, so it is looked for quoted, which no token on the page is,
    # and a message the render read is there in that form.
    %HTTPoison.Response{body: html} = HTTPoison.get!("http://localhost:4002/queries/8")

    assert html =~ ~s("there")
    refute html =~ ~s("bye")
    refute html =~ ~s("off-topic")
  end

  # Each of these changes the database once the client holds its fill, so what moves on screen is
  # what the stream told the browser, on the same page load.
  feature "moves a message into a channel's inverse in position order", %{session: session} do
    rows = seed_channels()

    session =
      session
      |> visit(Page8)
      |> await_local_fill()
      |> mark_this_page_load()

    DB.update!(Message, rows.bye.id, channel_id: rows.general.id)

    session
    |> assert_text(css("#channel_messages"), ~r/^general: hi, bye, there \| topic: welcome$/)
    |> assert_same_page_load()
  end

  feature "moves a message out of a channel's inverse", %{session: session} do
    rows = seed_channels()

    session =
      session
      |> visit(Page8)
      |> await_local_fill()
      |> mark_this_page_load()

    DB.update!(Message, rows.hi.id, channel_id: rows.random.id)

    session
    |> assert_text(css("#channel_messages"), ~r/^general: there \| topic: welcome$/)
    |> assert_same_page_load()
  end

  feature "adds a created message to its channel's inverse in position order", %{
    session: session
  } do
    rows = seed_channels()

    session =
      session
      |> visit(Page8)
      |> await_local_fill()
      |> mark_this_page_load()

    %{body: "fresh", channel_id: rows.general.id, position: 2}
    |> Message.new()
    |> DB.create!()

    session
    |> assert_text(
      css("#channel_messages"),
      ~r/^general: hi, fresh, there \| topic: welcome$/
    )
    |> assert_same_page_load()
  end

  feature "removes a deleted message from its channel's inverse", %{session: session} do
    rows = seed_channels()

    session =
      session
      |> visit(Page8)
      |> await_local_fill()
      |> mark_this_page_load()

    DB.delete!(Message, rows.there.id)

    session
    |> assert_text(css("#channel_messages"), ~r/^general: hi \| topic: welcome$/)
    |> assert_same_page_load()
  end

  feature "adds a message to a label's inverse when it gains the label", %{session: session} do
    rows = seed_channels()

    session =
      session
      |> visit(Page8)
      |> await_local_fill()
      |> mark_this_page_load()

    rows.bye
    |> add_relationship(:labels, rows.urgent.id)
    |> DB.update!()

    session
    |> assert_text(css("#label_messages"), ~r/^urgent: bye, hi, there$/)
    |> assert_same_page_load()
  end

  feature "removes a message from a label's inverse when it loses the label", %{session: session} do
    rows = seed_channels()

    session =
      session
      |> visit(Page8)
      |> await_local_fill()
      |> mark_this_page_load()

    rows.there
    |> delete_relationship(:labels, rows.urgent.id)
    |> DB.update!()

    session
    |> assert_text(css("#label_messages"), ~r/^urgent: hi$/)
    |> assert_same_page_load()
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

  # General's messages are created out of position order, so the order they render in is the
  # inverse's declared one - and random's bye sits between them, so a move into general shows
  # where it lands. Random and later are what the page's render never reads.
  defp seed_channels do
    general =
      %{name: "general"}
      |> Channel.new()
      |> DB.create!()

    random =
      %{name: "random"}
      |> Channel.new()
      |> DB.create!()

    %{channel_id: general.id, title: "welcome"}
    |> Topic.new()
    |> DB.create!()

    %{channel_id: random.id, title: "off-topic"}
    |> Topic.new()
    |> DB.create!()

    there =
      %{body: "there", channel_id: general.id, position: 3}
      |> Message.new()
      |> DB.create!()

    hi =
      %{body: "hi", channel_id: general.id, position: 1}
      |> Message.new()
      |> DB.create!()

    bye =
      %{body: "bye", channel_id: random.id, position: 2}
      |> Message.new()
      |> DB.create!()

    later =
      %{name: "later"}
      |> Label.new()
      |> DB.create!()

    urgent =
      %{name: "urgent"}
      |> Label.new()
      |> DB.create!()

    Enum.each([{bye, later}, {hi, later}, {hi, urgent}, {there, urgent}], fn {message, label} ->
      message
      |> add_relationship(:labels, label.id)
      |> DB.update!()
    end)

    %{bye: bye, general: general, hi: hi, random: random, there: there, urgent: urgent}
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
