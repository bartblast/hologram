defmodule HologramFeatureTests.RenderingTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Components.Rendering.PropValidationComponent
  alias HologramFeatureTests.Rendering.Page1
  alias HologramFeatureTests.Rendering.Page2
  alias HologramFeatureTests.Rendering.Page3
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
