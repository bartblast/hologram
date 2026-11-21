defmodule HologramFeatureTests.DataModelBundleTest do
  # async: false - the test truncates shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Queries.Page2

  # The app's data model comes in a bundle of its own, which the runtime waits for before it boots.
  # The checks after the visit rest on it waiting for the page to mount, which comes after that.
  #
  # The review table truncates too: its foreign key to the product table makes Postgres reject
  # truncating the referenced table alone.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join([Product, Review], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  feature "a page loads the data model from its own bundle", %{session: session} do
    %{name: "abacus"}
    |> Product.new()
    |> DB.create!()

    session =
      session
      |> visit(Page2)
      |> assert_text(css("#live_products"), ~r/^abacus$/)

    # A row the browser gets through sync, which its data layer can only take in with the model.
    %{name: "armchair"}
    |> Product.new()
    |> DB.create!()

    assert_text(session, css("#live_products"), ~r/^abacus,armchair$/)

    # The first render patches the script elements away, so the test asks the browser what it
    # fetched instead.
    assert script_result(session, """
           return performance
             .getEntriesByType("resource")
             .some((entry) => new URL(entry.name).pathname.startsWith("/hologram/data-model-"));
           """)

    model_hash = script_result(session, "return globalThis.Hologram.sync?.modelHash;")
    assert is_binary(model_hash) and model_hash != ""
  end
end
