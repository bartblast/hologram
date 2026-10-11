defmodule HologramEcosystemTests.Ash.PricedItemPageTest do
  use HologramEcosystemTests.TestCase, async: false

  alias Hologram.Assets.ChunkRegistry
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias HologramEcosystemTests.Ash.PricedItemPage
  alias HologramEcosystemTests.Bundles
  alias HologramEcosystemTestsWeb.Endpoint

  # The document the server answers a request for the page with, before any script has run.
  defp fetch_document do
    path = RouterHelpers.page_path(PricedItemPage)

    :get
    |> Plug.Test.conn(path)
    |> Endpoint.call(Endpoint.init([]))
    |> Map.fetch!(:resp_body)
  end

  feature "a money struct a command sends renders", %{session: session} do
    session
    |> visit(PricedItemPage)
    |> click(button("Reprice"))
    |> assert_text(css("#price"), "EUR 20")
  end

  feature "a money struct in the state renders", %{session: session} do
    session
    |> visit(PricedItemPage)
    |> assert_text(css("#price"), "EUR 10")
  end

  test "the money type's chunks are named in the page's document" do
    document = fetch_document()
    money_digests = ChunkRegistry.lookup_type(Money)

    assert money_digests != []

    for digest <- money_digests do
      assert String.contains?(
               document,
               ~s(<script async src="#{RouterHelpers.chunk_bundle_path(digest)}"></script>)
             )
    end

    [_match, initial_digests_json] =
      Regex.run(~r/globalThis\.Hologram\.initialChunkDigests = (\[[^\]]*\]);/, document)

    assert money_digests -- Jason.decode!(initial_digests_json) == []
  end

  # The page's client code names no money struct, so the chunk reaches the document through the
  # state alone.
  test "the page preloads none of the chunks that hold the money type's implementation" do
    for digest <- ChunkRegistry.lookup_page(PricedItemPage) do
      refute Bundles.chunk_defines?(digest, {String.Chars.Money, :to_string, 1})
    end
  end
end
