defmodule HologramFeatureTests.QuerySnapshotTest do
  # async: false - each test truncates the shared table.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.BigIntegersPage
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTests.QuerySnapshotPage

  setup do
    table = ~s("hologram_data"."#{Mapper.table_name(Todo)}")

    {:ok, _result} = Connection.query("TRUNCATE #{table}", [])

    :ok
  end

  defp create_todo(title, done) do
    %{done: done, title: title}
    |> Todo.new()
    |> DB.create!()
  end

  # Reloaded before going Back, so the snapshot comes from storage rather than from the live object
  # the document still holds.
  feature "keeps a query filtering on a boolean across a reload and Back", %{session: session} do
    create_todo("shown", true)
    create_todo("hidden", false)

    session
    |> visit(QuerySnapshotPage)
    |> click(button("Hold query"))
    |> assert_text(css("#result"), "held")
    |> click(link("Leave the page"))
    |> assert_page(BigIntegersPage)
    |> mark_document()
    |> reload()
    |> wait_for_unmarked_document()
    |> assert_page(BigIntegersPage)
    |> go_back()
    |> assert_page(QuerySnapshotPage)
    |> click(button("Read query"))
    |> assert_text(css("#result"), "read_[shown]")
  end
end
