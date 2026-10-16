defmodule HologramMinimalTests.RuntimeBundleTest do
  use ExUnit.Case, async: true

  defp read_runtime_bundle do
    [runtime_bundle_path] =
      [Application.app_dir(:hologram_minimal_tests, "priv"), "static", "hologram", "runtime-*.js"]
      |> Path.join()
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

  # What the test above stands on: the build picks its runtime's subsystems from the app's entity
  # types, and this app has none.
  test "declares no entity types" do
    assert Hologram.Reflection.list_entities() == []
  end
end
