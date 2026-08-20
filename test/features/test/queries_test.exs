defmodule HologramFeatureTests.QueriesTest do
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1]

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Queries.Page1
  alias HologramFeatureTests.Queries.Page3

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

  feature "renders a query filtering on a field of an entity prop", %{session: session} do
    seed_products_and_reviews()

    session
    |> visit(Page3)
    |> assert_text(css("#field_read"), "aa,bb")
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

  feature "renders from_query prop results in practical order", %{session: session} do
    Product
    |> Entity.new(name: "Zürich")
    |> create()

    Product
    |> Entity.new(name: "Łódź")
    |> create()

    Product
    |> Entity.new(name: "apple")
    |> create()

    session
    |> visit(Page1)
    |> assert_text(css("#products"), "apple,Łódź,Zürich")
  end

  # Two products so the parent's ordering picks a definite one to pass down, and reviews split
  # across both so a query filtering by the passed product reads fewer rows than one that does not.
  defp seed_products_and_reviews do
    alpha =
      Product
      |> Entity.new(name: "alpha")
      |> create()

    beta =
      Product
      |> Entity.new(name: "beta")
      |> create()

    Review
    |> Entity.new(body: "aa", product_id: alpha.id, rating: 2)
    |> create()

    Review
    |> Entity.new(body: "bb", product_id: alpha.id, rating: 5)
    |> create()

    Review
    |> Entity.new(body: "cc", product_id: beta.id, rating: 3)
    |> create()

    :ok
  end
end
