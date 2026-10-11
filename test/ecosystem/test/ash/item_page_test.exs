defmodule HologramEcosystemTests.Ash.ItemPageTest do
  use HologramEcosystemTests.TestCase, async: false

  alias Hologram.Assets.ChunkRegistry
  alias HologramEcosystemTests.Ash.Item
  alias HologramEcosystemTests.Ash.ItemPage
  alias HologramEcosystemTests.Bundles

  # The implementation that turns a money struct into text, and the function of the localization
  # library it formats the amount with.
  @money_to_string {String.Chars.Money, :to_string, 1}
  @number_to_string {Localize.Number, :to_string, 2}

  feature "the title taken out of the record renders", %{session: session} do
    session
    |> visit(ItemPage)
    |> assert_text(css("#title"), "title")
  end

  test "the money type's chunks define its struct functions" do
    money_digests = ChunkRegistry.lookup_type(Money)

    for arity <- [0, 1] do
      defining_digests =
        Enum.filter(money_digests, &Bundles.chunk_defines?(&1, {Money, :__struct__, arity}))

      assert [_defining_digest] = defining_digests
    end
  end

  test "the money type's implementation and the localization library are in chunks the money type needs, and in no other bundle" do
    money_digests = ChunkRegistry.lookup_type(Money)

    for function <- [@money_to_string, @number_to_string] do
      defining_digests =
        Enum.filter(Bundles.chunk_digests(), &Bundles.chunk_defines?(&1, function))

      assert [defining_digest] = defining_digests
      assert defining_digest in money_digests

      page_bundle = Bundles.page(ItemPage)
      runtime_bundle = Bundles.runtime()

      refute Bundles.defines?(page_bundle, function)
      refute Bundles.defines?(runtime_bundle, function)
    end
  end

  # The record's type and the money type are named by the page's init/3 alone, and the bundle holds
  # no struct function of any type: every struct type's are in its chunks.
  test "the page bundle defines no struct function" do
    page_bundle = Bundles.page(ItemPage)

    refute Bundles.defines?(page_bundle, {Item, :__struct__, 0})
    refute Bundles.defines?(page_bundle, {Money, :__struct__, 0})
    refute String.contains?(page_bundle, ~s/,"__struct__",0,/)
    refute String.contains?(page_bundle, ~s/,"__struct__",1,/)
  end

  # Only the title reaches the state, and the page's client code names no money struct. The page
  # can share small chunks with the money type (code both the money type and a type the runtime
  # builds need), so what is checked is the chunks that hold the money type's own code.
  test "the page preloads none of the chunks that hold the money type's implementation or the localization library" do
    preloaded_digests = ChunkRegistry.lookup_page(ItemPage)

    for function <- [@money_to_string, @number_to_string], digest <- preloaded_digests do
      refute Bundles.chunk_defines?(digest, function)
    end
  end
end
