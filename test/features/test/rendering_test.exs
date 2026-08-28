defmodule HologramFeatureTests.RenderingTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Components.Rendering.PropValidationComponent
  alias HologramFeatureTests.Rendering.Page1
  alias HologramFeatureTests.Rendering.Page2
  alias HologramFeatureTests.Rendering.Page3
  alias HologramFeatureTests.Rendering.Page4
  alias HologramFeatureTests.Rendering.PropsOnStructPage
  alias HologramFeatureTests.Rendering.PropValidationPage

  feature "root element without attributes", %{session: session} do
    session
    |> visit(Page1)
    |> assert_has(css("html"))
  end

  feature "root element with single attribute", %{session: session} do
    session
    |> visit(Page2)
    |> assert_has(css("html[attr_1='value_1']"))
  end

  feature "root element with multiple attributes", %{session: session} do
    session
    |> visit(Page3)
    |> assert_has(css("html[attr_1='value_1']"))
    |> assert_has(css("html[attr_2='value_2']"))
  end

  # The length is what pins the fix. The text is repaired by the client's own render on boot, so it
  # reads correctly either way, but the length was measured on the server and shipped, so it still
  # says what the server saw. Escaped, "a & b < c" would reach the component as "a &amp; b &lt; c"
  # and the count would be 16.
  feature "component prop written as text is the string the template wrote", %{session: session} do
    session
    |> visit(Page4)
    |> assert_text(css("#text"), "a & b < c")
    |> assert_text(css("#length"), "9")
  end

  describe "props on the component struct" do
    # The prop is changed after mount and then read in an action. A component that copied the prop
    # into state during init would answer 0 here forever, which is the trap this closes.
    feature "action reads the prop the latest render passed", %{session: session} do
      session
      |> visit(PropsOnStructPage, n: 1)
      |> click(button("Increment"))
      |> click(button("Increment"))
      |> assert_text(css("#component_1_prop_count"), "2")
      |> click(css("#component_1_read_prop"))
      |> assert_text(css("#component_1_result"), "2")
    end

    feature "action reads the prop on the first render", %{session: session} do
      session
      |> visit(PropsOnStructPage, n: 1)
      |> click(css("#component_1_read_prop"))
      |> assert_text(css("#component_1_result"), "0")
    end

    # Component 2 is not in the tree when the page loads, so it goes down the client's init/2 path
    # rather than being initialized on the server.
    feature "action reads the prop of a component added after load", %{session: session} do
      session
      |> visit(PropsOnStructPage, n: 1)
      |> click(button("Increment"))
      |> click(button("Increment"))
      |> click(button("Show component 2"))
      |> assert_text(css("#component_2_prop_count"), "2")
      |> click(css("#component_2_read_prop"))
      |> assert_text(css("#component_2_result"), "2")
    end

    feature "page action reads a URL param", %{session: session} do
      session
      |> visit(PropsOnStructPage, n: 7)
      |> click(button("Read param"))
      |> assert_text(css("#page_result"), "7")
    end
  end

  describe "prop validation" do
    # The component is reached through a spread, so the compiler can't judge the usage and the
    # client renderer is what enforces the contract.
    feature "renders when every prop honours its declaration", %{session: session} do
      session
      |> visit(PropValidationPage)
      |> click(button("Render valid"))
      |> assert_text(css("#prop_validation_result"), "my_label / small")
    end

    feature "raises when a required prop is missing", %{session: session} do
      expected_msg =
        ~s/component "#{inspect(PropValidationComponent)}" is missing required prop "label", / <>
          ~s/rendered from "#{inspect(PropValidationPage)}"/

      assert_client_error session, Hologram.PropError, expected_msg, fn ->
        session
        |> visit(PropValidationPage)
        |> click(button("Render without required prop"))
      end
    end

    feature "raises when a prop value is outside its :values list", %{session: session} do
      expected_msg =
        ~s/prop "size" of component "#{inspect(PropValidationComponent)}" must be one of / <>
          ~s/[:small, :large], got: :huge, rendered from "#{inspect(PropValidationPage)}"/

      assert_client_error session, Hologram.PropError, expected_msg, fn ->
        session
        |> visit(PropValidationPage)
        |> click(button("Render with invalid value"))
      end
    end
  end
end
