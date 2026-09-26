defmodule HologramFeatureTests.StructFieldTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias HologramFeatureTests.CallGraph.StructFieldPage

  defp read_bundles do
    static_dir = Application.app_dir(:hologram_feature_tests, "priv/static")
    digest = PageDigestRegistry.lookup(StructFieldPage)

    page_bundle_path =
      Path.join(static_dir, RouterHelpers.page_bundle_path(StructFieldPage, digest))

    [runtime_bundle_path] =
      static_dir
      |> Path.join("hologram/runtime-????????.js")
      |> Path.wildcard()

    %{page: File.read!(page_bundle_path), runtime: File.read!(runtime_bundle_path)}
  end

  feature "the title taken out of the struct renders", %{session: session} do
    session
    |> visit(StructFieldPage)
    |> assert_text(css("#title"), "title")
  end

  test "the implementation of the struct in another field is in no bundle" do
    %{page: page_bundle, runtime: runtime_bundle} = read_bundles()

    refute String.contains?(
             runtime_bundle,
             "String.Chars.HologramFeatureTests.StructFieldNoteFixture"
           )

    refute String.contains?(
             page_bundle,
             "String.Chars.HologramFeatureTests.StructFieldNoteFixture"
           )
  end
end
