defmodule HologramFeatureTests.DataApiTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.DataApiPage
  alias HologramFeatureTests.Entities.Account
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review

  # The review and product tables truncate in one statement: the review table's foreign key
  # to the product table makes Postgres reject truncating the referenced table alone. The
  # account table has no references and rides along.
  setup do
    account_table = Mapper.table_name(Account)
    product_table = Mapper.table_name(Product)
    review_table = Mapper.table_name(Review)

    statement =
      ~s(TRUNCATE "hologram_data"."#{review_table}", ) <>
        ~s("hologram_data"."#{product_table}", "hologram_data"."#{account_table}")

    {:ok, _result} = Connection.query(statement, [])

    :ok
  end

  feature "refuses a duplicate of a unique attribute's value as a structured violation", %{
    session: session
  } do
    session
    |> visit(DataApiPage)
    |> click(button("Create duplicate account"))
    |> assert_text(css("#result"), "duplicate_account_{:error, %{handle: [:unique]}}")
  end

  feature "raises on a duplicate through the bang variant", %{session: session} do
    session
    |> visit(DataApiPage)
    |> click(button("Raise on duplicate account"))
    |> assert_text(css("#result"), "cannot create HologramFeatureTests.Entities.Account:")
    |> assert_text(css("#result"), ~s(* attribute :handle "taken" is already taken))
  end

  feature "reports a value violation and a taken unique value in one pass", %{session: session} do
    session
    |> visit(DataApiPage)
    |> click(button("Create invalid duplicate account"))
    |> assert_text(
      css("#result"),
      "invalid_duplicate_account_{:error, %{bio: [max_length: 10], handle: [:unique]}}"
    )
  end

  feature "refuses updating into a taken unique value", %{session: session} do
    session
    |> visit(DataApiPage)
    |> click(button("Update into duplicate account"))
    |> assert_text(css("#result"), "updated_into_duplicate_{:error, %{handle: [:unique]}}")
  end

  feature "refuses deleting a row another entity still references, naming the referencer", %{
    session: session
  } do
    session
    |> visit(DataApiPage)
    |> click(button("Delete referenced product"))
    |> assert_text(
      css("#result"),
      "deleted_referenced_{:error, %{referenced_by: HologramFeatureTests.Entities.Review, relationship: :product}}"
    )
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
