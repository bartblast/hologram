defmodule HologramFeatureTests.DurabilityTest do
  # async: false - each test truncates the shared tables.
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias HologramFeatureTests.DurabilityPage
  alias HologramFeatureTests.Entities.Account
  alias HologramFeatureTests.Entities.Document
  alias HologramFeatureTests.Entities.Folder
  alias HologramFeatureTests.Entities.Item
  alias HologramFeatureTests.Entities.Note
  alias HologramFeatureTests.Entities.Product
  alias HologramFeatureTests.Entities.Review
  alias HologramFeatureTests.Entities.Shop
  alias HologramFeatureTests.Entities.Ticket
  alias HologramFeatureTests.Entities.Todo
  alias HologramFeatureTests.Entities.User
  alias HologramFeatureTests.Jobs.RestockItem

  # What the client held in memory until now it keeps between page loads, so these read the SECOND
  # visit rather than the first.
  #
  # The lever is emptying the SERVER between the two: a TRUNCATE writes nothing to the operations
  # log, so a returning client is never told the rows are gone and the stream has nothing to send
  # it. Anything on screen after that came out of the browser's own store, and there is no timing
  # to get right. (Holding the stream open instead does not work: `visit/3` blocks until the client
  # reports a connection, so a page whose stream never attaches never finishes visiting.)
  #
  # Every one of these leans on a Wallaby session being a fresh Chrome profile, and so an empty
  # store to begin with - nothing truncates a browser's database.

  setup do
    await_evaluator_drain()
    truncate_every_entity_table()

    :ok
  end

  # Every table, not only the products: the client's pot is app-wide, so a row left in ANY synced
  # table by an earlier file would arrive in the fill and could stand in for what the browser is
  # supposed to have kept. One statement, because PostgreSQL refuses to truncate a table another
  # one references without it.
  defp truncate_every_entity_table do
    tables =
      Enum.map_join(
        [
          Account,
          Document,
          Folder,
          Item,
          Note,
          Product,
          RestockItem,
          Review,
          RoleGrant,
          Shop,
          Ticket,
          Todo,
          User
        ],
        ", ",
        fn entity_type -> ~s("hologram_data"."#{Mapper.table_name(entity_type)}") end
      )

    {:ok, _result} = Connection.query("TRUNCATE #{tables}", [])
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

    truncate_every_entity_table()

    session
    |> visit(DurabilityPage)
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
    |> await_durable_writes()

    held = script_result(session, "return globalThis.Hologram.durability.replicaId();")

    session
    |> reload()
    |> assert_page(DurabilityPage)
    |> await_durable_writes()

    kept = script_result(session, "return globalThis.Hologram.durability.replicaId();")
    minted = script_result(session, "return globalThis.Hologram.replicaId;")

    # Every comparison below has two halves that can be nil - the client presents no identity until
    # one is adopted - and nil == nil would pass while proving neither that a pair was kept nor
    # that the page offered a different one. So each is pinned as a real id first.
    assert is_binary(held) and held != ""
    assert is_binary(kept) and kept != ""
    assert is_binary(minted) and minted != ""

    assert kept == held

    # The page did mint a fresh one, and the client is not presenting it.
    refute minted == held
  end

  # There is deliberately no feature here for the place a returning client resumes from, and the
  # reason is worth keeping: nothing a browser can be asked would discriminate. The completeness
  # marker now hands over a place on every connect, a first arrival included, so a client that
  # restored nothing still reports one - and the only honest signal, the `cursor` the greeting
  # carries, is not readable from a driven browser. A feature asserting it would pass whether or
  # not anything was restored, which is worse than not having one.
  #
  # What covers the claim instead: `durability_test.mjs`'s "fills the database with the stored rows
  # and answers the place they are dated at" for the round trip, and `sse_test.mjs`'s "keeps the
  # place the completeness marker names" for the frame that supplies it.
end
