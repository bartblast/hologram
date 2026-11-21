defmodule HologramMinimalTests.RuntimeBundleTest do
  use ExUnit.Case, async: true

  alias Hologram.Reflection

  defp read_runtime_bundle do
    [runtime_bundle_path] =
      Reflection.bundles_dir()
      |> Path.join("runtime-????????.js")
      |> Path.wildcard()

    File.read!(runtime_bundle_path)
  end

  # The data layer's client code is a module of its own, imported only by the runtime entry of a
  # build that declares entity types, so this one leaves it out of the bundle. The marker is a
  # string literal of that code, which survives minification.
  test "carries none of the data layer's client code" do
    bundle = read_runtime_bundle()

    # The positive artifact beside the negative one, so a bundle that failed to build cannot pass
    # this by holding nothing at all.
    assert String.contains?(bundle, "Hologram.config")

    refute String.contains?(bundle, "IndexedDB unavailable")
  end

  # A build without the data layer loads no data model bundle: its runtime sets the client's data
  # layer constants itself, so it waits for none.
  test "writes no data model bundle, and sets the data layer constants to null in the runtime" do
    assert String.contains?(read_runtime_bundle(), "globalThis.Hologram.sync=null;")

    assert Reflection.bundles_dir()
           |> Path.join("data-model-*")
           |> Path.wildcard() == []
  end

  # What the test above stands on: the build picks its runtime's subsystems from the app's entity
  # types, and this app has none.
  test "declares no entity types" do
    assert Hologram.Reflection.list_entities() == []
  end
end
