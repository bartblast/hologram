defmodule HologramFeatureTests.BigIntegersTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.BigIntegersPage
  alias HologramFeatureTests.Entities.Todo

  # One past the largest integer a JavaScript number holds exactly, and the neighbour it would
  # round to.
  @big 9_007_199_254_740_993
  @neighbour 9_007_199_254_740_992

  setup do
    table = ~s("hologram_data"."#{Mapper.table_name(Todo)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    :ok
  end

  defp create_todo(title, votes) do
    %{title: title, votes: votes}
    |> Todo.new()
    |> DB.create!()
  end

  feature "stores a big integer a browser wrote exactly", %{session: session} do
    session
    |> visit(BigIntegersPage)
    |> click(button("Create big"))
    |> assert_text(css("#result"), "created")
    |> assert_text(css("#todos"), "big #{@big}")

    assert %Todo{votes: @big} = await_server_votes(@big)
  end

  feature "shows a big integer from the page's own rows exactly", %{session: session} do
    create_todo("big", @big)

    # The stream is held back, or the rows it fills would stand in for the ones the page carried.
    session
    |> simulate_slow_sse_attach(5_000)
    |> visit("/big-integers")
    |> await_page_mount(BigIntegersPage)
    |> assert_text(css("#todos"), "big #{@big}")
  end

  feature "shows a big integer that arrives on the sync stream exactly", %{session: session} do
    session =
      session
      |> visit(BigIntegersPage)
      |> await_local_fill()

    create_todo("big", @big)

    assert_text(session, css("#todos"), "big #{@big}")
  end

  feature "tells a big integer from its neighbour in a filter", %{session: session} do
    create_todo("big", @big)
    create_todo("neighbour", @neighbour)

    session
    |> visit(BigIntegersPage)
    |> assert_text(css("#todos"), "neighbour #{@neighbour}")
    |> click(button("Find big"))
    |> assert_text(css("#result"), "found_[big]")
  end

  feature "sorts a big integer and its neighbour", %{session: session} do
    create_todo("neighbour", @neighbour)
    create_todo("big", @big)

    session
    |> visit(BigIntegersPage)
    |> assert_text(css("#todos li:first-child"), "big #{@big}")
    |> assert_text(css("#todos li:last-child"), "neighbour #{@neighbour}")
  end

  feature "moves a counter past what a JavaScript number holds exactly", %{session: session} do
    create_todo("big", 9_007_199_254_740_991)

    session
    |> visit(BigIntegersPage)
    |> assert_text(css("#todos"), "big 9007199254740991")
    |> click(button("Move big"))
    |> assert_text(css("#result"), "moved")
    |> assert_text(css("#todos"), "big #{@big}")

    assert %Todo{votes: @big} = await_server_votes(@big)
  end
end
