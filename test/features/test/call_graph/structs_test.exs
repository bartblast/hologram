defmodule HologramFeatureTests.StructsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.StructsPage

  describe "struct" do
    feature "create with defaults", %{session: session} do
      session
      |> visit(StructsPage)
      |> click(button("Create with defaults"))
      |> assert_text(css("#result"), inspect({"default", 0}))
    end

    feature "create with custom values", %{session: session} do
      session
      |> visit(StructsPage)
      |> click(button("Create with custom values"))
      |> assert_text(css("#result"), inspect({"custom", 42}))
    end
  end
end
