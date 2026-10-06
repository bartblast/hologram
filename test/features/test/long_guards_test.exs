defmodule HologramFeatureTests.LongGuardsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.LongGuardsPage

  # The number of values in each of the page's lists - keep in step with @value_count there.
  @value_count 600

  feature "atom list", %{session: session} do
    session
    |> visit(LongGuardsPage)
    |> click(button("Atom list"))
    |> assert_text(css("#result"), ":atom_match")
  end

  feature "binary list", %{session: session} do
    session
    |> visit(LongGuardsPage)
    |> click(button("Binary list"))
    |> assert_text(css("#result"), ":binary_match")
  end

  feature "case clause", %{session: session} do
    session
    |> visit(LongGuardsPage)
    |> click(button("Case clause"))
    |> assert_text(css("#result"), ":case_match")
  end

  feature "fall through to the next clause", %{session: session} do
    session
    |> visit(LongGuardsPage)
    |> click(button("Fall through"))
    |> assert_text(css("#result"), ":binary_no_match")
  end

  feature "integer list", %{session: session} do
    session
    |> visit(LongGuardsPage)
    |> click(button("Integer list"))
    |> assert_text(css("#result"), ":integer_match")
  end

  feature "loose chain", %{session: session} do
    session
    |> visit(LongGuardsPage)
    |> click(button("Loose chain"))
    |> assert_text(css("#result"), ":loose_match")
  end

  feature "mixed list", %{session: session} do
    session
    |> visit(LongGuardsPage)
    |> click(button("Mixed list"))
    |> assert_text(css("#result"), ":mixed_match")
  end

  feature "no matching clause", %{session: session} do
    attempted_guard = Enum.map_join(1..@value_count, " or ", &~s(-x === "Zone/#{&1}"-))

    assert_client_error session,
                        FunctionClauseError,
                        build_function_clause_error_msg(
                          "HologramFeatureTests.LongGuardsPage.only_binaries/1",
                          [123],
                          ["def only_binaries(x) when #{attempted_guard}"]
                        ),
                        fn ->
                          session
                          |> visit(LongGuardsPage)
                          |> click(button("No matching clause"))
                        end
  end
end
