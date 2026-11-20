defmodule HologramFeatureTests.DerivedTest do
  # async: false - each test truncates the shared table, and one the operations log.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias HologramFeatureTests.Derived.Page1
  alias HologramFeatureTests.Derived.Page2
  alias HologramFeatureTests.Derived.Page3
  alias HologramFeatureTests.Derived.Page4
  alias HologramFeatureTests.Entities.Ticket

  setup do
    await_evaluator_drain()
    truncate_entity_tables([Ticket])

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
end
