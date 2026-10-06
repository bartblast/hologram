defmodule HologramFeatureTests.StructFieldTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Assets.ChunkRegistry
  alias HologramFeatureTests.CallGraph.StructFieldPage
  alias HologramFeatureTests.StructFieldNoteFixture

  @note_to_string {String.Chars.HologramFeatureTests.StructFieldNoteFixture, :to_string, 1}

  feature "the title taken out of the struct renders", %{session: session} do
    session
    |> visit(StructFieldPage)
    |> assert_text(css("#title"), "title")
  end

  test "the implementation of the struct in another field is in a chunk of the struct's type and in no other bundle" do
    defining_digests = Enum.filter(chunk_digests(), &chunk_bundle_defines?(&1, @note_to_string))

    assert [defining_digest] = defining_digests
    assert defining_digest in ChunkRegistry.lookup_type(StructFieldNoteFixture)

    page_bundle = read_page_bundle(StructFieldPage)
    runtime_bundle = read_runtime_bundle()

    refute bundle_defines?(page_bundle, @note_to_string)
    refute bundle_defines?(runtime_bundle, @note_to_string)
  end

  test "the page's document names no chunk for the struct in another field" do
    named_digests = document_chunk_digests(StructFieldPage)

    refute Enum.any?(named_digests, &chunk_bundle_defines?(&1, @note_to_string))
  end
end
