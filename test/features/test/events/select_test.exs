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
    script = trigger_select_event_script("text_input")

    session
    |> visit(SelectPage)
    |> execute_script(script)
    |> assert_text(
      css("#result"),
      ~r/\{:text_input, %\{event: %\{value: &quot;am 1 Holo&quot;\}\}\}/
    )
  end

  feature "textarea", %{session: session} do
    script = trigger_select_event_script("textarea")

    session
    |> visit(SelectPage)
    |> execute_script(script)
    |> assert_text(
      css("#result"),
      ~r/\{:textarea, %\{event: %\{value: &quot;am 2 Holo&quot;\}\}\}/
    )
  end
end
