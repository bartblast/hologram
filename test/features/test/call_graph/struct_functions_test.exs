defmodule HologramFeatureTests.StructFunctionsTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Assets.ChunkRegistry
  alias HologramFeatureTests.CallGraph.ClientCreatedStructsPage
  alias HologramFeatureTests.CallGraph.DynamicReflectionPage
  alias HologramFeatureTests.CallGraph.PushedModulePage
  alias HologramFeatureTests.CallGraph.UnnamedModulePage
  alias HologramFeatureTests.StructFixture1
  alias HologramFeatureTests.UnnamedStructFixture

  # The struct functions of the fixture no app code names, which the two module pages hand to the
  # browser as a module atom, and of the fixture a page's init/3 puts into the state as a module
  # and another page's client code builds a struct of.
  @unnamed_struct_functions [
    {UnnamedStructFixture, :__struct__, 0},
    {UnnamedStructFixture, :__struct__, 1}
  ]
  @named_struct_functions [{StructFixture1, :__struct__, 0}, {StructFixture1, :__struct__, 1}]

  feature "a module atom a command sends builds its struct in an action", %{session: session} do
    session
    |> visit(PushedModulePage)
    |> click(button("Load"))
    |> assert_text(css("#built"), "unnamed(built from a pushed module)")
  end

  feature "a module atom in the initial state builds its struct in an action", %{session: session} do
    session
    |> visit(UnnamedModulePage)
    |> click(button("Build"))
    |> assert_text(css("#built"), "unnamed(built from the module)")
  end

  test "a page preloads the chunk of a struct type its client code builds" do
    named_digests = document_chunk_digests(ClientCreatedStructsPage)

    assert Enum.any?(named_digests, &chunk_bundle_defines?(&1, {StructFixture1, :__struct__, 1}))
  end

  test "a struct type's struct functions are defined in one chunk of the type, and in no page bundle or the runtime" do
    page_bundles = [
      read_page_bundle(ClientCreatedStructsPage),
      read_page_bundle(DynamicReflectionPage)
    ]

    runtime_bundle = read_runtime_bundle()

    for {type, struct_functions} <- [
          {StructFixture1, @named_struct_functions},
          {UnnamedStructFixture, @unnamed_struct_functions}
        ],
        struct_function <- struct_functions do
      defining_digests = Enum.filter(chunk_digests(), &chunk_bundle_defines?(&1, struct_function))

      assert [defining_digest] = defining_digests
      assert defining_digest in ChunkRegistry.lookup_type(type)

      refute Enum.any?(page_bundles, &bundle_defines?(&1, struct_function))
      refute bundle_defines?(runtime_bundle, struct_function)
    end
  end

  # Otherwise the browser would have the chunk before the reply, and the reply would not be what
  # brings it.
  test "the document of the page a module atom is pushed to names no chunk for its type" do
    named_digests = document_chunk_digests(PushedModulePage)

    refute Enum.any?(
             named_digests,
             &chunk_bundle_defines?(&1, {UnnamedStructFixture, :__struct__, 0})
           )
  end

  test "the document of a page whose state holds a module atom names the type's chunks" do
    named_digests = document_chunk_digests(UnnamedModulePage)
    type_digests = ChunkRegistry.lookup_type(UnnamedStructFixture)

    assert type_digests != []
    assert Enum.all?(type_digests, &(&1 in named_digests))
  end
end
