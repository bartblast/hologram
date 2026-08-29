defmodule HologramFeatureTests.DurabilityTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.DurabilityPage
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Entities.Ticket

  # What the client held in memory until now it keeps between page loads, so these read the second
  # visit rather than the first. The lever throughout is a stream that never attaches: with no
  # frames arriving, anything on screen came out of the browser's own store.
  #
  # Every one of these leans on a Wallaby session being a fresh Chrome profile, and so an empty
  # store. Nothing truncates a browser's database - a TRUNCATE writes no effects to the log either,
  # so a client resuming from a stored place is never told the rows are gone.

  # Review references Product, so PostgreSQL refuses to truncate the referenced table alone.
  setup do
    await_evaluator_drain()

    tables =
      Enum.map_join([Product, Review, Ticket], ", ", fn entity_type ->
        ~s("hologram_data"."#{Mapper.table_name(entity_type)}")
      end)

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])

    :ok
  end

  # Blocks until the runtime has attached its window and settled whatever it had to write - which
  # is also the earliest moment anything below may be read out of the browser.
  defp await_runtime(session) do
    await_durable_writes(session)
  end

  # A stream held open long past anything Wallaby waits for, so no frame can arrive during the
  # visit that follows. Navigates away first, since a cookie needs a document to be set on.
  defp without_a_stream(session) do
    simulate_slow_sse_attach(session, 60_000)
  end

  feature "shows rows the page did not carry, out of what the browser kept", %{session: session} do
    %{name: "abacus"}
    |> Product.new()
    |> DB.create!()

    %{name: "armchair"}
    |> Product.new()
    |> DB.create!()

    session
    |> visit(DurabilityPage)
    |> click(button("Show products"))
    |> assert_text(css("#live_products"), ~r/^abacus,armchair$/)
    |> await_durable_writes()
    |> without_a_stream()
    |> visit(DurabilityPage)
    |> await_runtime()
    |> click(button("Show products"))
    |> assert_text(css("#live_products"), ~r/^abacus,armchair$/)
    |> assert_script_result(
      "return globalThis.Hologram.durability.mode();",
      "indexeddb"
    )
  end

  # The page offers a fresh pair on every load and a browser already holding one ignores it -
  # re-minting per load would abandon the numbering its batches are identified by.
  feature "keeps the identity it was given across a page load", %{session: session} do
    session
    |> visit(DurabilityPage)
    |> await_runtime()

    held = script_result(session, "return globalThis.Hologram.durability.replicaId();")

    session
    |> reload()
    |> assert_page(DurabilityPage)
    |> await_runtime()

    assert script_result(session, "return globalThis.Hologram.durability.replicaId();") ==
             held

    # The page did mint a fresh one, and the client is not presenting it.
    refute script_result(session, "return globalThis.Hologram.replicaId;") == held
  end

  # The place is what earns a returning client a catch-up rather than the whole database again.
  feature "knows where it left off before a stream says anything", %{session: session} do
    %{name: "bicycle"}
    |> Product.new()
    |> DB.create!()

    session
    |> visit(DurabilityPage)
    |> click(button("Show products"))
    |> assert_text(css("#live_products"), ~r/^bicycle$/)
    |> await_durable_writes()
    |> without_a_stream()
    |> visit(DurabilityPage)
    |> await_runtime()
    |> assert_script_result(
      "return globalThis.Hologram.durability.cursor() !== null;",
      true
    )
  end
end
