defmodule HologramEcosystemTests.Ash.ItemPageTest do
  use HologramEcosystemTests.TestCase, async: false

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias HologramEcosystemTests.Ash.ItemPage

  defp read_bundles do
    static_dir = Application.app_dir(:hologram_ecosystem_tests, "priv/static")
    digest = PageDigestRegistry.lookup(ItemPage)
    page_bundle_path = Path.join(static_dir, RouterHelpers.page_bundle_path(ItemPage, digest))

    [runtime_bundle_path] =
      static_dir
      |> Path.join("hologram/runtime-????????.js")
      |> Path.wildcard()

    %{page: File.read!(page_bundle_path), runtime: File.read!(runtime_bundle_path)}
  end

  feature "the title taken out of the record renders", %{session: session} do
    session
    |> visit(ItemPage)
    |> assert_text(css("#title"), "title")
  end

  test "the money type's implementation and the localization library are in no bundle" do
    %{page: page_bundle, runtime: runtime_bundle} = read_bundles()

    for bundle <- [page_bundle, runtime_bundle] do
      refute String.contains?(bundle, "String.Chars.Money")
      refute String.contains?(bundle, "Localize.")
    end
  end
end
