defmodule HologramFeatureTests.ProtocolsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.ProtocolsPage

  describe "protocol" do
    feature "dispatch for atom", %{session: session} do
      session
      |> visit(ProtocolsPage)
      |> click(button("Dispatch for atom"))
      |> assert_text(css("#result"), inspect("atom(hello)"))
    end

    feature "dispatch for struct", %{session: session} do
      session
      |> visit(ProtocolsPage)
      |> click(button("Dispatch for struct"))
      |> assert_text(css("#result"), inspect("<<7|test>>"))
    end
  end
end
