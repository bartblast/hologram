defmodule HologramFeatureTests.ProtocolsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.ProtocolsPage

  describe "custom protocol" do
    feature "dispatch for atom", %{session: session} do
      session
      |> visit(ProtocolsPage)
      |> click(button("Dispatch custom for atom"))
      |> assert_text(css("#result"), inspect("atom(hello)"))
    end

    feature "dispatch for struct", %{session: session} do
      session
      |> visit(ProtocolsPage)
      |> click(button("Dispatch custom for struct"))
      |> assert_text(css("#result"), inspect("<<7|test>>"))
    end
  end

  describe "Enumerable" do
    feature "dispatch for list", %{session: session} do
      session
      |> visit(ProtocolsPage)
      |> click(button("Dispatch Enumerable for list"))
      |> assert_text(css("#result"), inspect([30, 60, 90]))
    end

    feature "dispatch for custom struct", %{session: session} do
      session
      |> visit(ProtocolsPage)
      |> click(button("Dispatch Enumerable for struct"))
      |> assert_text(css("#result"), inspect([20, 40, 60]))
    end
  end
end
