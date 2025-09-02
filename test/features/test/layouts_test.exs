defmodule HologramFeatureTests.LayoutsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Layouts.NoPropsPage
  alias HologramFeatureTests.Layouts.PropsPassedExplicitelyPage
  alias HologramFeatureTests.Layouts.PropsPassedImplicitelyPage

  feature "no props", %{session: session} do
    session
    |> visit(NoPropsPage)
    |> assert_text(css("#layout_result"), "%{cid: &quot;layout&quot;}")
  end

  feature "props passed explicitely", %{session: session} do
    session
    |> visit(PropsPassedExplicitelyPage)
    |> assert_text(
      css("#layout_result"),
      "%{a: &quot;abc&quot;, b: 123, cid: &quot;layout&quot;}"
    )
  end

  feature "props passed implicitely", %{session: session} do
    session
    |> visit(PropsPassedImplicitelyPage)
    |> assert_text(
      css("#layout_result"),
      "%{a: &quot;abc&quot;, b: 123, cid: &quot;layout&quot;}"
    )
  end
end
