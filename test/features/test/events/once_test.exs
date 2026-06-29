defmodule HologramFeatureTests.Events.OnceTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.OncePage

  feature "fires the action once, then stops re-dispatching", %{session: session} do
    session
    |> visit(OncePage)
    |> click(css("#click_button"))
    |> click(css("#click_button"))
    |> click(css("#click_button"))
    |> assert_text(css("#click_result"), "1")
  end
end
