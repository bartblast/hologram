defmodule HologramFeatureTests.QueriesTest do
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1]

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Queries.Page1

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
end
