defmodule HologramFeatureTests.RefsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Refs.Page1
  alias HologramFeatureTests.Refs.Page2

  describe "JS.element/1" do
    feature "returns the element under a ref, for a JS function to act on", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Focus search"))
      |> assert_has(css("#page_1_search:focus"))
    end

    feature "returns the element under a keyed ref of a loop item", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Read item"))
      |> assert_text(css("#page_1_result"), "item: Item 2")
    end

    feature "returns the document for :document", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Read document"))
      |> assert_text(css("#page_1_result"), "document: HTML")
    end

    feature "returns the window for :window", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Read window"))
      |> assert_text(css("#page_1_result"), "window: /refs/1")
    end

    feature "returns a native value unchanged", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Pass native value"))
      |> assert_text(css("#page_1_result"), "native value: page_1_search")
    end

    feature "returns the element under a ref kept in state and passed to a component as a prop",
            %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Read field"))
      |> assert_text(css("#page_2_result"), "field: refs_field")
    end

    feature "returns an element of the layout to a page action", %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Read layout header"))
      |> assert_text(css("#page_2_result"), "layout header: Refs layout header")
    end

    feature "returns, in a chained action, the element the first action's state change rendered",
            %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Show details"))
      |> assert_text(css("#page_2_result"), "details: Details text")
    end

    feature "returns the element a ref moved to in the last render", %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Read swapped element"))
      |> assert_text(css("#page_2_result"), "swapped element: First element")
      |> click(button("Toggle swap"))
      |> click(button("Read swapped element"))
      |> assert_text(css("#page_2_result"), "swapped element: Second element")
    end

    feature "returns the elements of the page a navigation shows", %{session: session} do
      session
      |> visit(Page1)
      |> click(link("Go to page 2"))
      |> assert_page(Page2)
      |> click(button("Read note"))
      |> assert_text(css("#page_2_result"), "note: Page 2 note")
    end

    # A history restore mounts the page from its snapshot, with no interim patch before its first
    # render.
    feature "returns the elements of the page a history Back restores", %{session: session} do
      session
      |> visit(Page1)
      |> click(link("Go to page 2"))
      |> assert_page(Page2)
      |> go_back()
      |> assert_page(Page1)
      |> click(button("Read third item"))
      |> assert_text(css("#page_1_result"), "third item: Item 3")
    end
  end
end
