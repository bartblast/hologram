defmodule HologramFeatureTests.CompoundKeyTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.CompoundKeyPage
  alias HologramFeatureTests.Entities.Reaction

  @violations "%{emoji: [unique: [:reactor, :emoji]], reactor: [unique: [:reactor, :emoji]]}"

  @key_violation "{:error, #{@violations}}"

  defp await_server_reactions(expected_count) do
    Enum.reduce_while(1..100, [], fn _attempt, _acc ->
      reactions = server_reactions()

      if length(reactions) == expected_count do
        {:halt, reactions}
      else
        Process.sleep(50)
        {:cont, reactions}
      end
    end)
  end

  defp server_reactions do
    Reaction
    |> DB.read()
    |> Enum.map(&{&1.reactor, &1.emoji})
    |> Enum.sort()
  end

  # Reaction references nothing, so it truncates alone. Every test starts from the one row whose
  # key the page's writes repeat.
  setup do
    await_evaluator_drain()

    table = ~s("hologram_data"."#{Mapper.table_name(Reaction)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    %{emoji: "thumbs_up", reactor: "ann"}
    |> Reaction.new()
    |> DB.create!()

    :ok
  end

  feature "refuses a create repeating a key, naming every field of the key", %{session: session} do
    session
    |> visit(CompoundKeyPage)
    |> click(button("Repeat a key on the server"))
    |> assert_text(css("#result"), "repeated_key_#{@key_violation}")

    assert server_reactions() == [{"ann", "thumbs_up"}]
  end

  feature "refuses an update that leaves a row repeating a key", %{session: session} do
    session
    |> visit(CompoundKeyPage)
    |> click(button("Update into a repeated key"))
    |> assert_text(css("#result"), "updated_into_repeated_key_#{@key_violation}")

    assert server_reactions() == [{"ann", "heart"}, {"ann", "thumbs_up"}]
  end

  feature "raises on a repeated key through the bang variant, naming the key once", %{
    session: session
  } do
    session =
      session
      |> visit(CompoundKeyPage)
      |> click(button("Raise on a repeated key"))
      |> assert_text(css("#result"), "cannot create")

    expected =
      "cannot create HologramFeatureTests.Entities.Reaction:\n" <>
        ~s(  * key [:reactor, :emoji] is already taken \(reactor "ann", emoji "thumbs_up"\))

    assert script_result(session, "return document.querySelector('#result').textContent;") ==
             expected
  end

  # The browser cannot judge a key, so the row shows first and goes away when the server refuses
  # the batch that carried it.
  feature "rolls back a row written in the browser whose key is taken", %{session: session} do
    session =
      session
      |> visit(CompoundKeyPage)
      |> assert_text(css("#reactions"), "ann thumbs_up")

    session
    |> click(button("React again in the browser"))
    |> assert_text(css("#result"), "reacted_again")

    assert [%{"reason" => @violations, "rows" => [_row], "seq" => 1, "write" => 0}] =
             await_rejected_writes(session)

    assert_has(session, css("#reactions li", count: 1))

    assert server_reactions() == [{"ann", "thumbs_up"}]
  end

  # One action is one batch, refused whole: the row that repeats nothing goes with the one whose
  # key is taken, and the refusal names the write it came from.
  feature "rolls back every row of a batch written in the browser when one repeats a key", %{
    session: session
  } do
    session =
      session
      |> visit(CompoundKeyPage)
      |> assert_text(css("#reactions"), "ann thumbs_up")

    session
    |> click(button("React twice in the browser"))
    |> assert_text(css("#result"), "reacted_twice")

    assert [%{"reason" => @violations, "rows" => [_free, _repeated], "seq" => 1, "write" => 1}] =
             await_rejected_writes(session)

    assert_has(session, css("#reactions li", count: 1))
    refute_text(session, css("#reactions"), "bob")

    assert server_reactions() == [{"ann", "thumbs_up"}]
  end

  feature "keeps a row written in the browser that shares only part of a key", %{
    session: session
  } do
    session =
      session
      |> visit(CompoundKeyPage)
      |> assert_text(css("#reactions"), "ann thumbs_up")

    session
    |> click(button("React with another emoji in the browser"))
    |> assert_text(css("#result"), "reacted_with_heart")
    |> assert_text(css("#reactions"), "ann heart")

    assert await_server_reactions(2) == [{"ann", "heart"}, {"ann", "thumbs_up"}]
    assert script_result(session, "return globalThis.Hologram.writes.rejected();") == []
  end
end
