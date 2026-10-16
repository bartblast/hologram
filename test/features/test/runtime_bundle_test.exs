defmodule HologramFeatureTests.RuntimeBundleTest do
  use ExUnit.Case, async: true

  import HologramFeatureTests.Helpers,
    only: [chunk_digests: 0, read_chunk_bundle: 1, read_page_bundle: 1, read_runtime_bundle: 0]

  alias Hologram.Reflection

  # The data layer's client code is a module of its own, imported only by the runtime entry of a
  # build that declares entity types. This app declares them, so its runtime carries the code and
  # nothing else does: a page or a chunk holding it would ship it a second time.
  #
  # The marker is a string literal of the data layer's own code, which survives minification.
  @data_layer_marker "IndexedDB unavailable"

  test "no page or chunk bundle carries the data layer's client code" do
    page_modules = Reflection.list_pages()
    digests = chunk_digests()

    # Neither list is empty, so a build that wrote no bundles cannot pass this by checking nothing.
    assert page_modules != []
    assert digests != []

    carrying_pages = Enum.filter(page_modules, &carries_data_layer?(read_page_bundle(&1)))
    carrying_chunks = Enum.filter(digests, &carries_data_layer?(read_chunk_bundle(&1)))

    assert carrying_pages == []
    assert carrying_chunks == []
  end

  test "the runtime bundle carries the data layer's client code" do
    assert carries_data_layer?(read_runtime_bundle())
  end

  defp carries_data_layer?(bundle) do
    String.contains?(bundle, @data_layer_marker)
  end
end
