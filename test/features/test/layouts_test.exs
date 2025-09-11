defmodule HologramFeatureTests.LayoutsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Layouts.NoPropsPage
  alias HologramFeatureTests.Layouts.PropsPassedExplicitelyPage
  alias HologramFeatureTests.Layouts.PropsPassedImplicitelyPage

  feature "no props", %{session: session} do
    session
    |> visit(NoPropsPage)
    |> assert_text(css("#layout_result"), ~s'%{cid: "layout"}')
  end

  feature "props passed explicitely", %{session: session} do
    session
    |> visit(PropsPassedExplicitelyPage)
    |> assert_text(css("#layout_result"), ~s'%{a: "abc", b: 123, cid: "layout"}')
  end

  feature "props passed implicitely", %{session: session} do
    session
    |> visit(PropsPassedImplicitelyPage)
    |> assert_text(css("#layout_result"), ~s'%{a: "abc", b: 123, cid: "layout"}')
  end
end
