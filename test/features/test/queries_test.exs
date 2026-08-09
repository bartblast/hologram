defmodule HologramFeatureTests.QueriesTest do
  use HologramFeatureTests.TestCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1]

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Queries.Page1

  setup do
    table = Mapper.table_name(Product)

    {:ok, _result} = Connection.query(~s(TRUNCATE "hologram_data"."#{table}"), [])

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
