defmodule HologramEcosystemTests.PageTest do
  use HologramEcosystemTests.TestCase, async: false

  alias HologramEcosystemTests.PlainPage

  feature "a page request is served", %{session: session} do
    session
    |> visit(PlainPage)
    |> assert_text(css("#text"), "Served with the ecosystem libraries")
  end
end
