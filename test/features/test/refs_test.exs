defmodule HologramFeatureTests.RefsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Refs.Page1
  alias HologramFeatureTests.Refs.Page2
  alias HologramFeatureTests.Refs.Page3

  @chained_action_hint "a template declares the ref, but nothing renders it right now. " <>
                         "An element the action's own state change renders is on the page only once the action returns, " <>
                         "so look it up in an action chained with put_action/2"

  describe "JS.element/1" do
    feature "returns the element under a ref, for a JS function to act on", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Focus search"))
      |> assert_has(css("#page_1_search:focus"))
    end

    feature "returns the element under a tuple ref of a loop item", %{session: session} do
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

    feature "raises for a ref a template declares and nothing renders", %{session: session} do
      session = visit(session, Page3)

      assert_client_error session,
                          Hologram.MisuseError,
                          "no element is rendered under the ref :hidden - #{@chained_action_hint}",
                          fn -> click(session, button("Read hidden")) end
    end

    feature "raises for an element the action's own state change renders", %{session: session} do
      session = visit(session, Page3)

      assert_client_error session,
                          Hologram.MisuseError,
                          "no element is rendered under the ref :late - #{@chained_action_hint}",
                          fn -> click(session, button("Show and read late")) end
    end

    # The suggestion comes from the refs the page's bundle carries.
    feature "raises for a misspelled ref, suggesting the closest one the page declares",
            %{session: session} do
      session = visit(session, Page3)

      assert_client_error session,
                          Hologram.MisuseError,
                          "no element is rendered under the ref :serch - did you mean :search?",
                          fn -> click(session, button("Read misspelled ref")) end
    end
  end

  describe "$ref" do
    # Both refs come from expressions, so the build can't see them clash, and they clash only in
    # the render that follows the action.
    feature "raises for two elements under one ref, naming both components", %{session: session} do
      session = visit(session, Page3)

      assert_client_error session,
                          Hologram.MisuseError,
                          "two elements are rendered under the ref :first_paragraph, " <>
                            ~s(one from "HologramFeatureTests.Components.Refs.FirstParagraph" ) <>
                            ~s(and one from "HologramFeatureTests.Components.Refs.SecondParagraph" - ) <>
                            "a ref names one element, so give each element a ref of its own, " <>
                            "like {:first_paragraph, item.id} for the items of a loop",
                          fn -> click(session, button("Clash refs")) end
    end
  end
end
