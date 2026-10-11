defmodule HologramFeatureTests.DynamicReflectionTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.DynamicReflectionPage

  describe "__struct__ on a module read from state" do
    feature "through struct/2", %{session: session} do
      session
      |> visit(DynamicReflectionPage)
      |> click(button("Build with struct/2"))
      |> assert_text(css("#result"), inspect({"default", 0}))
    end

    feature "through struct!/2", %{session: session} do
      session
      |> visit(DynamicReflectionPage)
      |> click(button("Build with struct!/2"))
      |> assert_text(css("#result"), inspect({"custom", 42}))
    end

    feature "through a dot", %{session: session} do
      session
      |> visit(DynamicReflectionPage)
      |> click(button("Build with a dot"))
      |> assert_text(css("#result"), inspect({"default", 0}))
    end
  end

  describe "schema reflection on a module read from state" do
    feature "__changeset__/0", %{session: session} do
      session
      |> visit(DynamicReflectionPage)
      |> click(button("Read __changeset__/0"))
      |> assert_text(css("#result"), inspect(%{name: :string}))
    end

    feature "__schema__/1", %{session: session} do
      session
      |> visit(DynamicReflectionPage)
      |> click(button("Read __schema__/1"))
      |> assert_text(css("#result"), inspect([:name]))
    end
  end
end
