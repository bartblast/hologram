defmodule HologramFeatureTests.Events.ChangeTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.Events.ChangePage

  feature "text input", %{session: session} do
    session
    |> visit(ChangePage)
    |> fill_in(css("#text_input_elem"), with: "changed text")
    |> click(button("Blur"))
    |> assert_text(
      css("#result"),
      ~r/\{"text input", %\{event: %\{value: "changed text"\}\}\}/
    )
  end

  feature "textarea", %{session: session} do
    session
    |> visit(ChangePage)
    |> fill_in(css("#textarea_elem"), with: "changed textarea")
    |> click(button("Blur"))
    |> assert_text(
      css("#result"),
      ~r/\{"textarea", %\{event: %\{value: "changed textarea"\}\}\}/
    )
  end

  feature "checkbox, checked to unchecked", %{session: session} do
    session
    |> visit(ChangePage)
    # Uncheck it since it starts checked
    |> click(css("#checkbox_elem"))
    |> assert_text(
      css("#result"),
      ~r/\{"checkbox", %\{event: %\{value: false\}\}\}/
    )
  end

  feature "checkbox, unchecked to checked", %{session: session} do
    session
    |> visit(ChangePage)
    # Uncheck it first
    |> click(css("#checkbox_elem"))
    # Then check it again
    |> click(css("#checkbox_elem"))
    |> assert_text(
      css("#result"),
      ~r/\{"checkbox", %\{event: %\{value: true\}\}\}/
    )
  end

  feature "radio button, unselected to selected", %{session: session} do
    session
    |> visit(ChangePage)
    # The first radio button starts unselected
    |> click(css("#radio_elem_1"))
    |> assert_text(
      css("#result"),
      ~r/\{"radio", %\{event: %\{value: true\}\}\}/
    )
  end

  feature "radio button, changing selection within group", %{session: session} do
    session
    |> visit(ChangePage)
    # The first radio button starts unselected, so click it first
    |> click(css("#radio_elem_1"))
    # Now click the second radio button - this shouldn't fire a change event for the first radio button
    # because radio buttons only fire change events when they become selected, not unselected
    |> click(css("#radio_elem_2"))
    |> assert_text(
      css("#result"),
      ~r/\{"radio", %\{event: %\{value: true\}\}\}/
    )
  end

  feature "select dropdown", %{session: session} do
    session
    |> visit(ChangePage)
    |> click(css("#select_elem"))
    |> click(css("option[value='option_3']"))
    |> assert_text(
      css("#result"),
      ~r/\{"select", %\{event: %\{value: "option_3"\}\}\}/
    )
  end
end
