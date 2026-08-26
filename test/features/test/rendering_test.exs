defmodule HologramFeatureTests.RenderingTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Rendering.Page1
  alias HologramFeatureTests.Rendering.Page2
  alias HologramFeatureTests.Rendering.Page3
  alias HologramFeatureTests.Rendering.Page4

  feature "root element without attributes", %{session: session} do
    session
    |> visit(Page1)
    |> assert_has(css("html"))
  end

  feature "root element with single attribute", %{session: session} do
    session
    |> visit(Page2)
    |> assert_has(css("html[attr_1='value_1']"))
  end

  feature "root element with multiple attributes", %{session: session} do
    session
    |> visit(Page3)
    |> assert_has(css("html[attr_1='value_1']"))
    |> assert_has(css("html[attr_2='value_2']"))
  end

  # The length is what pins the fix. The text is repaired by the client's own render on boot, so it
  # reads correctly either way, but the length was measured on the server and shipped, so it still
  # says what the server saw. Escaped, "a & b < c" would reach the component as "a &amp; b &lt; c"
  # and the count would be 16.
  feature "component prop written as text is the string the template wrote", %{session: session} do
    session
    |> visit(Page4)
    |> assert_text(css("#text"), "a & b < c")
    |> assert_text(css("#length"), "9")
  end
end
