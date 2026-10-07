defmodule HologramFeatureTests.ProtocolChunksTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Assets.ChunkRegistry
  alias HologramFeatureTests.CallGraph.ProtocolChunksPage
  alias HologramFeatureTests.CallGraph.PushedStructsPage
  alias HologramFeatureTests.CallGraph.ServerCreatedStructsPage
  alias HologramFeatureTests.CallGraph.UnnamedStructPage
  alias HologramFeatureTests.StructFixture3
  alias HologramFeatureTests.StructFixture4
  alias HologramFeatureTests.StructFixture5

  @pushed_channel :pushed_structs

  # The String.Chars implementation of each struct fixture: of the one a page's init/3 puts in the
  # state, the one a command sends, the one a broadcast sends, the one a broadcast pushes to a
  # page that has not met it, and the one no app code names.
  @broadcast_to_string {String.Chars.HologramFeatureTests.StructFixture5, :to_string, 1}
  @command_to_string {String.Chars.HologramFeatureTests.StructFixture4, :to_string, 1}
  @init_to_string {String.Chars.HologramFeatureTests.StructFixture3, :to_string, 1}
  @pushed_to_string {String.Chars.HologramFeatureTests.PushedStructFixture, :to_string, 1}
  @unnamed_to_string {String.Chars.HologramFeatureTests.UnnamedStructFixture, :to_string, 1}

  # The destination's chunks arrive with the navigation's payload here, not with a document.
  feature "a struct in the state of a page navigated to renders", %{session: session} do
    session
    |> visit(ProtocolChunksPage)
    |> click(link("Server created structs"))
    |> assert_page(ServerCreatedStructsPage)
    |> assert_text(css("#init-result"), "struct(created in init)")
  end

  feature "a struct whose type no code names renders after a client re-render", %{
    session: session
  } do
    session
    |> visit(UnnamedStructPage)
    |> assert_text(css("#unnamed"), "unnamed(created from a string)")
    |> click(button("Relabel"))
    |> assert_text(css("#label"), "relabeled")
    |> assert_text(css("#unnamed"), "unnamed(created from a string)")
  end

  # The first broadcast carries a struct whose chunk neither tab has, so its action waits for the
  # chunk while the second one, which needs none, is free to run. Realtime promises no order, so
  # the test asserts that both ran and nothing about which ran first. Do not make it assert an
  # order.
  @sessions 2
  feature "two broadcasts from one handler both run when the first brings a struct type the tab has not met",
          %{sessions: [session_1, session_2]} do
    session_1 = visit(session_1, PushedStructsPage)
    session_2 = visit(session_2, PushedStructsPage)

    # Both connections must be subscribed before the broadcast.
    wait_for_subscription(session_2, @pushed_channel, 2)

    click(session_1, button("Push"))

    # The originating tab gets both as self-echoes in the command's reply.
    assert_text(session_1, css("#plain-result"), "plain")
    assert_text(session_1, css("#struct-result"), "pushed struct(pushed)")

    # The other tab gets them as two events on its stream.
    assert_text(session_2, css("#plain-result"), "plain")
    assert_text(session_2, css("#struct-result"), "pushed struct(pushed)")
  end

  test "a page's document names the chunk of a struct its state holds, and none for a struct that arrives later" do
    named_digests = document_chunk_digests(ServerCreatedStructsPage)

    assert Enum.any?(named_digests, &chunk_bundle_defines?(&1, @init_to_string))
    refute Enum.any?(named_digests, &chunk_bundle_defines?(&1, @broadcast_to_string))
    refute Enum.any?(named_digests, &chunk_bundle_defines?(&1, @command_to_string))
  end

  test "a page's document names the chunk of a struct whose type no code names" do
    named_digests = document_chunk_digests(UnnamedStructPage)

    assert Enum.any?(named_digests, &chunk_bundle_defines?(&1, @unnamed_to_string))
  end

  # Otherwise the tabs would have the chunk before the broadcast, and its action would not wait.
  test "the document of the page a struct is pushed to names no chunk for it" do
    named_digests = document_chunk_digests(PushedStructsPage)

    refute Enum.any?(named_digests, &chunk_bundle_defines?(&1, @pushed_to_string))
  end

  test "the implementation of a struct that server code sends is in a chunk of the struct's type and in no other bundle" do
    page_bundle = read_page_bundle(ServerCreatedStructsPage)
    runtime_bundle = read_runtime_bundle()

    for {type, to_string} <- [
          {StructFixture3, @init_to_string},
          {StructFixture4, @command_to_string},
          {StructFixture5, @broadcast_to_string}
        ] do
      defining_digests = Enum.filter(chunk_digests(), &chunk_bundle_defines?(&1, to_string))

      assert [defining_digest] = defining_digests
      assert defining_digest in ChunkRegistry.lookup_type(type)

      refute bundle_defines?(page_bundle, to_string)
      refute bundle_defines?(runtime_bundle, to_string)
    end
  end
end
