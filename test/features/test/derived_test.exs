defmodule HologramFeatureTests.DerivedTest do
  # async: false - each test truncates the shared tables, and one the operations log.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.Derived.Page1
  alias HologramFeatureTests.Derived.Page2
  alias HologramFeatureTests.Derived.Page3
  alias HologramFeatureTests.Derived.Page4
  alias HologramFeatureTests.Derived.Page5
  alias HologramFeatureTests.Derived.Page6
  alias HologramFeatureTests.Derived.Page7
  alias HologramFeatureTests.Derived.Page8
  alias HologramFeatureTests.Derived.Page9
  alias HologramFeatureTests.Entities.Bottle
  alias HologramFeatureTests.Entities.Crate
  alias HologramFeatureTests.Entities.Ticket
  alias HologramFeatureTests.Entities.Waybill

  setup do
    truncate_entity_tables([Bottle, Crate, Ticket, Waybill])

    :ok
  end

  # Bravo is the excluded title and charlie is low.
  feature "renders a derived query and a value computed from it", %{session: session} do
    create_tickets(alpha: :high, bravo: :high, charlie: :low, foxtrot: :high)

    session
    |> visit(Page1)
    |> assert_text(css("#tickets"), ~r/^alpha,foxtrot$/)
    |> assert_text(css("#summary"), ~r{^ALPHA/FOXTROT$})
  end

  # The page names the struct, and only the struct's protocol implementation names the entity type,
  # so its rows reach the browser only if the build reads that implementation.
  feature "renders a query written in a struct's protocol implementation", %{session: session} do
    create_waybill("alpha", true)
    create_waybill("bravo", false)

    session =
      session
      |> visit(Page8)
      |> await_local_fill()
      |> assert_text(css("#urgent_count"), ~r/^1$/)
      |> mark_this_page_load()

    create_waybill("charlie", true)

    session
    |> assert_text(css("#urgent_count"), ~r/^2$/)
    |> assert_same_page_load()
  end

  # Init picks high, and the click switches to low - the value computed from the rows follows them.
  feature "recomputes a derived query when the state it reads changes", %{session: session} do
    create_tickets(india: :high, juliet: :low)

    session
    |> visit(Page1)
    |> assert_text(css("#tickets"), ~r/^india$/)
    |> click(button("Show low"))
    |> assert_text(css("#tickets"), ~r/^juliet$/)
    |> assert_text(css("#summary"), ~r/^JULIET$/)
  end

  # Nothing here dispatches an action or reloads: the row arrives on the sync stream, and the
  # derived query answers again over the client's own database.
  feature "keeps a derived query current when a row it reads is created", %{session: session} do
    create_tickets(november: :high)

    session
    |> visit(Page1)
    |> await_local_fill()
    |> assert_text(css("#tickets"), ~r/^november$/)
    |> mark_this_page_load()

    create_tickets(oscar: :high)

    session
    |> assert_text(css("#tickets"), ~r/^november,oscar$/)
    |> assert_text(css("#summary"), ~r{^NOVEMBER/OSCAR$})
    |> assert_same_page_load()
  end

  # The payload is fetched over HTTP rather than read with page_source/1, since the browser reports
  # the DOM after the client rendered it again. Quebec is low, and the server reads init's priority.
  feature "renders the values init's state gives in the server's HTML", %{session: session} do
    create_tickets(hotel: :high, quebec: :low)

    session
    |> visit(Page1)
    |> assert_text(css("#tickets"), ~r/^hotel$/)

    %HTTPoison.Response{body: html} = HTTPoison.get!(http_url() <> "/derived/1")

    assert html =~ ~r{id="tickets"><code>hotel</code>}
    assert html =~ ~r{id="summary"><code>HOTEL</code>}
  end

  # The copy is taken after the click recomputed the fields, so the action reads the low ticket's
  # summary rather than the one the first render computed.
  feature "hands an action the derived fields", %{session: session} do
    create_tickets(kilo: :high, papa: :low)

    session
    |> visit(Page1)
    |> assert_text(css("#copied_summary"), ~r/^none$/)
    |> click(button("Show low"))
    |> assert_text(css("#tickets"), ~r/^papa$/)
    |> click(button("Copy summary"))
    |> assert_text(css("#copied_summary"), ~r/^PAPA$/)
  end

  # Mike is another title.
  feature "renders a page's derived field read from a param", %{session: session} do
    create_tickets(lima: :medium, mike: :medium)

    session
    |> visit(Page2, title: "lima")
    |> assert_text(css("#page_tickets"), ~r/^lima:medium$/)
  end

  # A count reaches the browser as the number the server rendered, held until the browser has every
  # ticket. The page is reached with the refill held back, so the browser holds the tickets of the
  # first fill and not foxtrot and golf, written since, which only the server's numbers count.
  # Lowering alpha in the browser turns the first count into a query the server never counted, which
  # the browser counts over its own tickets. The second count reads only alpha's id, so it keeps the
  # server's number.
  #
  # Emptying the operations log is the lever for the refill, as in the resync tests: the client's
  # place is one the log can no longer speak for, so it is told to start over.
  feature "counts the query it now runs rather than the one the page carried",
          %{session: session} do
    session
    |> visit_counts_during_refill()
    |> click(button("Lower alpha"))
    |> assert_text(css("#same_priority"), ~r/^4$/)
    |> assert_text(css("#others"), ~r/^6$/)
    # Holding no place says the refill was still held back when the counts were read.
    |> assert_no_place()
    |> release_sync_frames()
    |> assert_text(css("#same_priority"), ~r/^5$/)
    |> assert_text(css("#others"), ~r/^6$/)
    |> assert_same_page_load()

    # The write settles before the next test empties the table it lands in.
    assert %Ticket{priority: :low} = await_server_ticket("alpha", :low)
  end

  # Another page's visit is what used to take the numbers away. Hotel, written after the Back, is
  # counted only by the browser, so seeing it says the page let go of the server's numbers once the
  # browser held every ticket.
  feature "keeps the server's counts when Back returns to a page during a fill",
          %{session: session} do
    session
    |> visit_counts_during_refill()
    |> click(link("Away link"))
    |> assert_page(Page3)
    |> go_back()
    |> assert_page(Page4)
    |> assert_text(css("#same_priority"), ~r/^3$/)
    |> assert_text(css("#others"), ~r/^6$/)
    |> assert_no_place()

    create_tickets(hotel: :high)

    session
    |> release_sync_frames()
    |> assert_text(css("#same_priority"), ~r/^4$/)
    |> assert_text(css("#others"), ~r/^7$/)
    |> assert_same_page_load()
  end

  # The new stream's marker comes after its greeting, the point that used to take the numbers away.
  # The render the click makes is what would show it.
  feature "keeps the server's count through a reconnect during a fill", %{session: session} do
    rearmed =
      session
      |> visit_counts_during_refill()
      |> await_held_all_marker()
      |> hold_sync_frames()

    simulate_sse_disconnect(current_instance_id(rearmed))

    rearmed
    |> await_held_all_marker()
    |> click(button("Lower alpha"))
    |> assert_text(css("#same_priority"), ~r/^4$/)
    |> assert_text(css("#others"), ~r/^6$/)
    |> assert_no_place()
    |> release_sync_frames()
    |> assert_text(css("#same_priority"), ~r/^5$/)
    |> assert_text(css("#others"), ~r/^6$/)
    |> assert_same_page_load()

    assert %Ticket{priority: :low} = await_server_ticket("alpha", :low)
  end

  # The first tab leads and holds the fill back, so the second, which follows, can reload without
  # starting a fill of its own. Its reloaded document never received the page's count, and holds no
  # tickets, so only the snapshot can bring the number back.
  feature "keeps the server's count when Back returns to a page saved before a reload",
          %{session: session} do
    create_tickets(alpha: :high, bravo: :low)

    leading =
      session
      |> visit(Page3)
      |> await_local_fill()
      |> await_durable_writes()
      |> hold_sync_frames()

    first = tab_handle(leading)

    truncate_oplog()
    simulate_sse_disconnect(current_instance_id(leading))

    leading
    |> await_held_sync_frame()
    |> assert_no_place()

    create_tickets(charlie: :low)

    following =
      leading
      |> open_tab(Page9)
      |> assert_text(css("#total"), ~r/^3$/)
      |> click(link("Away link"))
      |> assert_page(Page3)
      |> mark_document()
      |> reload()
      |> wait_for_unmarked_document()
      |> assert_page(Page3)
      |> mark_this_page_load()
      |> go_back()
      |> assert_page(Page9)
      |> assert_text(css("#total"), ~r/^3$/)
      |> assert_no_place()
      |> assert_same_page_load()

    second = tab_handle(following)

    create_tickets(delta: :low)

    following
    |> focus_tab(first)
    |> release_sync_frames()
    |> focus_tab(second)
    |> assert_text(css("#total"), ~r/^4$/)
  end

  # Bravo and delta are the excluded titles. The build can't read either query - one is folded over
  # a list, the other built by a helper calling itself - so each runs as written, on the server
  # and then in the browser, where a row written since joins it.
  feature "renders and keeps current a query built by folding over a list or by recursion",
          %{session: session} do
    create_tickets(alpha: :high, bravo: :high, charlie: :low, delta: :medium)

    session
    |> visit(Page5)
    |> await_local_fill()
    |> assert_text(css("#reduced"), ~r/^alpha,charlie$/)
    |> assert_text(css("#recursed"), ~r/^alpha,charlie$/)
    |> mark_this_page_load()

    create_tickets(echo: :low)

    session
    |> assert_text(css("#reduced"), ~r/^alpha,charlie,echo$/)
    |> assert_text(css("#recursed"), ~r/^alpha,charlie,echo$/)
    |> assert_same_page_load()
  end

  # The page builds the query on the server and hands it to the component in its state, so the
  # browser rebuilds it from what the server sent and answers it over its own database.
  feature "keeps current in the browser a query the server built and a component was handed",
          %{session: session} do
    create_tickets(india: :high, juliet: :low)

    session
    |> visit(Page6)
    |> await_local_fill()
    |> assert_text(css("#handed_tickets"), ~r/^india$/)
    |> mark_this_page_load()

    create_tickets(kilo: :high)

    session
    |> assert_text(css("#handed_tickets"), ~r/^india,kilo$/)
    |> assert_same_page_load()
  end

  # No browser code names the bottle module: the page reaches bottles only by the relationship name
  # it includes and reads, so that name is what makes them sync, and a bottle changed since the
  # page rendered reaches it on the sync stream.
  feature "keeps current a row of a type reached only through an include", %{session: session} do
    crate =
      [name: "north"]
      |> Crate.new()
      |> DB.create!()

    ale =
      [crate_id: crate.id, label: "ale"]
      |> Bottle.new()
      |> DB.create!()

    [crate_id: crate.id, label: "beer"]
    |> Bottle.new()
    |> DB.create!()

    session
    |> visit(Page7)
    |> await_local_fill()
    |> assert_text(css("#crates"), ~r/^north:ale,beer$/)
    |> mark_this_page_load()

    DB.update!(Bottle, ale.id, label: "cider")

    session
    |> assert_text(css("#crates"), ~r/^north:beer,cider$/)
    |> assert_same_page_load()
  end

  defp await_server_ticket(title, priority) do
    Enum.reduce_while(1..100, nil, fn _attempt, _acc ->
      ticket =
        Ticket
        |> DB.read()
        |> Enum.find(&(&1.title == title))

      if ticket.priority == priority do
        {:halt, ticket}
      else
        Process.sleep(50)
        {:cont, ticket}
      end
    end)
  end

  defp create_tickets(priorities) do
    Enum.each(priorities, fn {title, priority} ->
      %{priority: priority, title: Atom.to_string(title)}
      |> Ticket.new()
      |> DB.create!()
    end)
  end

  defp create_waybill(code, urgent) do
    %{code: code, urgent: urgent}
    |> Waybill.new()
    |> DB.create!()
  end

  # Page4 reached with the refill held back. The browser holds the five tickets of the first fill
  # and not foxtrot and golf, written since, which only the server's numbers count.
  defp visit_counts_during_refill(session) do
    create_tickets(alpha: :high, bravo: :high, charlie: :low, delta: :low, echo: :low)

    session =
      session
      |> visit(Page3)
      |> await_local_fill()
      |> mark_this_page_load()
      |> hold_sync_frames()

    truncate_oplog()
    simulate_sse_disconnect(current_instance_id(session))

    session
    |> await_held_sync_frame()
    |> assert_no_place()

    create_tickets(foxtrot: :low, golf: :high)

    session
    |> click(link("Ticket counts link"))
    |> assert_page(Page4)
    |> assert_text(css("#same_priority"), ~r/^3$/)
    |> assert_text(css("#others"), ~r/^6$/)
  end
end
