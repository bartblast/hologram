defmodule HologramFeatureTests.TransientServerStructsTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Assets.ChunkRegistry
  alias HologramFeatureTests.CallGraph.TransientServerStructsPage
  alias HologramFeatureTests.ReachedStructFixture
  alias HologramFeatureTests.TransientStructFixture

  @reached_to_string {String.Chars.HologramFeatureTests.ReachedStructFixture, :to_string, 1}
  @transient_to_string {String.Chars.HologramFeatureTests.TransientStructFixture, :to_string, 1}

  feature "a struct built and dropped on the server renders its text", %{session: session} do
    session
    |> visit(TransientServerStructsPage)
    |> assert_text(css("#transient-text"), "transient(transient)")
  end

  feature "a struct that reaches the state through a helper renders after a client re-render",
          %{session: session} do
    session
    |> visit(TransientServerStructsPage)
    |> assert_text(css("#reached"), "reached(reached)")
    |> click(button("Relabel"))
    |> assert_text(css("#label"), "relabeled")
    |> assert_text(css("#reached"), "reached(reached)")
  end

  feature "structs built in a closure render on the client", %{session: session} do
    session
    |> visit(TransientServerStructsPage)
    |> assert_text(css("#items"), "reached(item 1)reached(item 2)")
  end

  test "the implementation of a struct, dropped on the server or put in the state, is in a chunk of the struct's type and in no other bundle" do
    page_bundle = read_page_bundle(TransientServerStructsPage)
    runtime_bundle = read_runtime_bundle()

    for {type, to_string} <- [
          {ReachedStructFixture, @reached_to_string},
          {TransientStructFixture, @transient_to_string}
        ] do
      defining_digests = Enum.filter(chunk_digests(), &chunk_bundle_defines?(&1, to_string))

      assert [defining_digest] = defining_digests
      assert defining_digest in ChunkRegistry.lookup_type(type)

      refute bundle_defines?(page_bundle, to_string)
      refute bundle_defines?(runtime_bundle, to_string)
    end
  end

  test "the page's document names the chunk of the struct put in the state, and none for the struct dropped on the server" do
    named_digests = document_chunk_digests(TransientServerStructsPage)

    assert Enum.any?(named_digests, &chunk_bundle_defines?(&1, @reached_to_string))
    refute Enum.any?(named_digests, &chunk_bundle_defines?(&1, @transient_to_string))
  end
end
