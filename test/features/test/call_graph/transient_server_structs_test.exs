defmodule HologramFeatureTests.TransientServerStructsTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias HologramFeatureTests.CallGraph.TransientServerStructsPage

  defp read_bundles do
    static_dir = Application.app_dir(:hologram_feature_tests, "priv/static")
    digest = PageDigestRegistry.lookup(TransientServerStructsPage)

    page_bundle_path =
      Path.join(static_dir, RouterHelpers.page_bundle_path(TransientServerStructsPage, digest))

    [runtime_bundle_path] =
      static_dir
      |> Path.join("hologram/runtime-????????.js")
      |> Path.wildcard()

    %{page: File.read!(page_bundle_path), runtime: File.read!(runtime_bundle_path)}
  end

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

  test "the implementation of a struct built and dropped on the server is in no bundle" do
    %{page: page_bundle, runtime: runtime_bundle} = read_bundles()

    refute String.contains?(
             runtime_bundle,
             "String.Chars.HologramFeatureTests.TransientStructFixture"
           )

    refute String.contains?(
             page_bundle,
             "String.Chars.HologramFeatureTests.TransientStructFixture"
           )

    assert String.contains?(
             runtime_bundle,
             "String.Chars.HologramFeatureTests.ReachedStructFixture"
           )
  end
end
