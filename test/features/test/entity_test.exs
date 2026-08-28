defmodule HologramFeatureTests.EntityTest do
  # async: true - nothing here writes, and no test touches a shared table.
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.EntityPage

  # Every one of these runs the ported Entity.new or Entity.validate in the BROWSER. What makes
  # them worth running at all is that the answers come from declarations no entity module ships
  # here - the build bakes them into the model, and the port reads that.

  feature "applies a declared default when constructing a row", %{session: session} do
    session
    |> visit(EntityPage)
    |> click(button("Build with defaults"))
    |> assert_text(css("#result"), "defaults_0_nil")
  end

  feature "a bare struct carries the declared defaults", %{session: session} do
    session
    |> visit(EntityPage)
    |> click(button("Read a bare struct"))
    |> assert_text(css("#result"), "bare_0_nil")
  end

  feature "judges a whole struct against a declared bound", %{session: session} do
    session
    |> visit(EntityPage)
    |> click(button("Check a whole struct"))
    |> assert_text(css("#result"), "struct_0")
  end

  feature "judges changes against a declared range", %{session: session} do
    session
    |> visit(EntityPage)
    |> click(button("Check a range"))
    |> assert_text(css("#result"), "changes_1_5")
  end

  # The pattern travels as its source and is compiled in the browser, so a violation carries back
  # a regex struct rather than the text the declaration held.
  feature "judges changes against a declared pattern", %{session: session} do
    session
    |> visit(EntityPage)
    |> click(button("Check a pattern"))
    |> assert_text(css("#result"), "format_@")
  end

  feature "accepts changes that satisfy every declaration", %{session: session} do
    session
    |> visit(EntityPage)
    |> click(button("Accept good changes"))
    |> assert_text(css("#result"), "valid_:ok")
  end

  feature "refuses a relationship assigned at construction, in the server's words", %{
    session: session
  } do
    expected =
      "refused_relationship :product of HologramFeatureTests.Entities.Review cannot be " <>
        "assigned at construction - set a to-one reference via the :product_id field, " <>
        "to-many edges via add_relationship"

    session
    |> visit(EntityPage)
    |> click(button("Assign a relationship"))
    |> assert_text(css("#result"), expected)
  end
end
