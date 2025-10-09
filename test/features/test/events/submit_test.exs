defmodule HologramFeatureTests.Events.SubmitTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.Events.SubmitPage

  feature "submit event", %{session: session} do
    session
    |> visit(SubmitPage)
    |> fill_in(css("form input[name='non_empty_text']"), with: "my_text")
    |> click(button("Submit"))
    |> assert_text(
      css("#result"),
      ~s'{:form, %{event: %{"checked_checkbox" => true, "empty_email" => "", "empty_text" => "", "empty_textarea" => "", "non_empty_email" => "my_email@test.com", "non_empty_text" => "my_text", "non_empty_textarea" => "my_textarea", "radio_group" => "option_2", "single_select" => "option_3"}}}'
    )
  end
end
