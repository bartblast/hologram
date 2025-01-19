defmodule HologramFeatureTests.JavaScriptInteropTest do
  use HologramFeatureTests.TestCase, async: true

  # Multi-letter uppercase sigils were introduced in Elixir 1.15.0,
  # see: https://github.com/elixir-lang/elixir/blob/v1.15/CHANGELOG.md
  if Version.match?(System.version(), ">= 1.15.0") do
    feature "~JS sigil", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Run JavaScript snippet"))
      |> assert_text(css("#result"), "Hologram")
    end
  end
end
