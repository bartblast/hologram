defmodule HologramFeatureTests.SharedFunctionsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.SharedFunctionsPage1
  alias HologramFeatureTests.CallGraph.SharedFunctionsPage2
  alias HologramFeatureTests.CallGraph.SharedFunctionsPage3

  feature "a page reaching only fun_a", %{session: session} do
    session
    |> visit(SharedFunctionsPage1)
    |> click(button("Call fun_a"))
    |> assert_text(css("#result"), inspect("fun_a"))
  end

  feature "a page reaching only fun_b", %{session: session} do
    session
    |> visit(SharedFunctionsPage2)
    |> click(button("Call fun_b"))
    |> assert_text(css("#result"), inspect("fun_b"))
  end

  feature "a page reaching both functions gets both", %{session: session} do
    session
    |> visit(SharedFunctionsPage3)
    |> click(button("Call fun_a"))
    |> assert_text(css("#result"), inspect("fun_a"))
    |> click(button("Call fun_b"))
    |> assert_text(css("#result"), inspect("fun_b"))
  end
end
