defmodule HologramFeatureTests.AssetManifestTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.AssetManifestPage

  # The static dir holds a file whose path carries a quote, a backslash and a closing script tag
  # (planted by test_helper.exs). The server writes every static path into the inline script the
  # browser reads its asset manifest from, so an unescaped path breaks that script: the page
  # never mounts, and the client cannot resolve the asset. The second path assertion runs after
  # a client-side render, so it reads the manifest the browser parsed, not the server's.
  #
  # Windows cannot hold such a file name - every character that makes it hostile is illegal
  # there - so the bug cannot occur on Windows and this test never applies to it.
  @tag :skip_on_windows
  feature "static file named with the chars a script cannot carry raw", %{session: session} do
    session
    |> visit(AssetManifestPage)
    |> assert_text(css("#path"), ~S|/hostile/quote"backslash\tag</script>.txt|)
    |> click(css("#button"))
    |> assert_text(css("#status"), "clicked")
    |> assert_text(css("#path"), ~S|/hostile/quote"backslash\tag</script>.txt|)
  end
end
