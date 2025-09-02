defmodule HologramFeatureTests.Events.ChangeTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.Events.ChangePage

  feature "text input", %{session: session} do
    session
    |> visit(ChangePage)
    |> fill_in(css("#text_input_elem"), with: "abc text")
    |> assert_text(
      css("#result"),
      ~r/\{:text_input, %\{event: %\{value: &quot;abc text&quot;\}\}\}/
    )
    |> fill_in(css("#text_input_elem"), with: "xyz text")
    |> click(button("Blur"))
    |> assert_text(
      css("#result"),
      ~r/\{:text_input, %\{event: %\{value: &quot;xyz text&quot;\}\}\}/
    )
  end

  feature "email input", %{session: session} do
    session
    |> visit(ChangePage)
    |> fill_in(css("#email_input_elem"), with: "abc email")
    |> assert_text(
      css("#result"),
      ~r/\{:email_input, %\{event: %\{value: &quot;abc email&quot;\}\}\}/
    )
    |> fill_in(css("#email_input_elem"), with: "xyz email")
    |> click(button("Blur"))
    |> assert_text(
      css("#result"),
      ~r/\{:email_input, %\{event: %\{value: &quot;xyz email&quot;\}\}\}/
    )
  end

  feature "textarea", %{session: session} do
    session
    |> visit(ChangePage)
    |> fill_in(css("#textarea_elem"), with: "abc textarea")
    |> assert_text(
      css("#result"),
      ~r/\{:textarea, %\{event: %\{value: &quot;abc textarea&quot;\}\}\}/
    )
    |> fill_in(css("#textarea_elem"), with: "xyz textarea")
    |> click(button("Blur"))
    |> assert_text(
      css("#result"),
      ~r/\{:textarea, %\{event: %\{value: &quot;xyz textarea&quot;\}\}\}/
    )
  end

  feature "checkbox, checked to unchecked", %{session: session} do
    session
    |> visit(ChangePage)
    # Uncheck it since it starts checked
    |> click(css("#checkbox_elem"))
    |> assert_text(
      css("#result"),
      ~r/\{:checkbox, %\{event: %\{value: false\}\}\}/
    )
  end

  feature "checkbox, unchecked to checked", %{session: session} do
    session
    |> visit(ChangePage)
    # Uncheck it first since it starts checked
    |> click(css("#checkbox_elem"))
    # Then check it again
    |> click(css("#checkbox_elem"))
    |> assert_text(
      css("#result"),
      ~r/\{:checkbox, %\{event: %\{value: true\}\}\}/
    )
  end

  feature "radio button, unselected to selected", %{session: session} do
    session
    |> visit(ChangePage)
    # The first radio button starts unselected
    |> click(css("#radio_elem_1"))
    |> assert_text(
      css("#result"),
      ~r/\{:radio, %\{event: %\{value: true\}\}\}/
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
      ~r/\{:radio, %\{event: %\{value: true\}\}\}/
    )
  end

  feature "single select, changing selection", %{session: session} do
    session
    |> visit(ChangePage)
    # Start with option_2 selected
    # Change selection to option_3 (this automatically deselects option_2)
    |> click(css("#single_select_elem"))
    |> click(css("#single_select_elem option[value='option_3']"))
    |> assert_text(
      css("#result"),
      ~r/\{:single_select, %\{event: %\{value: &quot;option_3&quot;\}\}\}/
    )
  end

  feature "multiple select, adding option", %{session: session} do
    session
    |> visit(ChangePage)
    # Start with option_2 and option_3 selected
    # Use JavaScript to programmatically select option_1 to add it to the selection
    |> execute_script("""
      const select = document.querySelector("#multiple_select_elem");
      const option1 = select.querySelector("option[value='option_1']");
      option1.selected = true;
      // Programmatic DOM changes don't automatically fire events
      // We need to manually dispatch the change event to trigger Hologram's event handler
      select.dispatchEvent(new Event('change', {bubbles: true}));
    """)
    |> assert_text(
      css("#result"),
      ~r/\{:multiple_select, %\{event: %\{value: \[&quot;option_1&quot;, &quot;option_2&quot;, &quot;option_3&quot;\]\}\}\}/
    )
  end

  feature "multiple select, removing option", %{session: session} do
    session
    |> visit(ChangePage)
    # Start with option_2 and option_3 selected
    # Use JavaScript to programmatically deselect option_2
    |> execute_script("""
      const select = document.querySelector("#multiple_select_elem");
      const option2 = select.querySelector("option[value='option_2']");
      option2.selected = false;
      // Programmatic DOM changes don't automatically fire events
      // We need to manually dispatch the change event to trigger Hologram's event handler
      select.dispatchEvent(new Event('change', {bubbles: true}));
    """)
    |> assert_text(
      css("#result"),
      ~r/\{:multiple_select, %\{event: %\{value: \[&quot;option_3&quot;\]\}\}\}/
    )
  end
end
