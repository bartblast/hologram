defmodule HologramFeatureTests.Events.SelectTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.Events.SelectPage

  defp trigger_select_event_script(elem_id) do
    """
      const elem = document.querySelector("##{elem_id}");
      elem.focus();
      elem.setSelectionRange(6, 15);
      
      const event = new Event("select", {bubbles: true});
      elem.dispatchEvent(event);
      
      return true;
    """
  end

  feature "text input", %{session: session} do
    script = trigger_select_event_script("text_input_elem")

    session
    |> visit(SelectPage)
    |> execute_script(script)
    |> assert_text(
      css("#result"),
      ~r/\{"text input", %\{event: %\{value: "am 1 Holo"\}\}\}/
    )
  end

  feature "text area", %{session: session} do
    script = trigger_select_event_script("text_area_elem")

    session
    |> visit(SelectPage)
    |> execute_script(script)
    |> assert_text(
      css("#result"),
      ~r/\{"text area", %\{event: %\{value: "am 2 Holo"\}\}\}/
    )
  end
end
