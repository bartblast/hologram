defmodule HologramFeatureTests.DataApiTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.DataApiPage
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review

  # Both tables truncate in one statement: the review table's foreign key to the
  # product table makes Postgres reject truncating the referenced table alone.
  setup do
    product_table = Mapper.table_name(Product)
    review_table = Mapper.table_name(Review)

    statement =
      ~s(TRUNCATE "hologram_data"."#{review_table}", "hologram_data"."#{product_table}")

    {:ok, _result} = Connection.query(statement, [])

    :ok
  end

  feature "writes an entity and reads it back", %{session: session} do
    session
    |> visit(DataApiPage)
    |> click(button("Create review"))
    |> assert_text(css("#result"), "created_review_4")
  end

  feature "rejects a write violating a declared constraint", %{session: session} do
    session
    |> visit(DataApiPage)
    |> click(button("Reject invalid review"))
    |> assert_text(css("#result"), "attribute :rating must be in 1..5, got: 0")
  end

  feature "runs a filtered and ordered query", %{session: session} do
    session
    |> visit(DataApiPage)
    |> click(button("Run query"))
    |> assert_text(css("#result"), "run_query_apple,run_query_banana")
  end

  feature "validates changes without writing", %{session: session} do
    session
    |> visit(DataApiPage)
    |> click(button("Validate changes"))
    |> assert_text(css("#result"), "validated_{:error, %{rating: [in: 1..5]}}")
  end
end
