defmodule HologramFeatureTests.Events.DisabledBindingTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Events.DisabledBindingPage

  # Clicks are dispatched in order, so asserting on a later verified action's update proves the
  # earlier disabled clicks have settled, while the rendered state tuple proves they changed
  # nothing.

  feature "disabled bindings dispatch nothing while the page stays functional",
          %{session: session} do
    session
    |> visit(DisabledBindingPage)
    |> click(css("#disabled_longhand_action"))
    |> click(css("#disabled_longhand_action_with_params"))
    |> click(css("#disabled_longhand_command"))
    |> click(css("#disabled_shorthand"))
    |> click(css("#ping"))
    |> assert_text(css("#result"), "{nil, nil, false, true}")
  end

  feature "conditional binding dispatches only once enabled", %{session: session} do
    session
    |> visit(DisabledBindingPage)
    |> click(css("#conditional"))
    |> click(css("#enable"))
    |> assert_text(css("#result"), "{nil, nil, true, false}")
    |> click(css("#conditional"))
    |> assert_text(css("#result"), "{:executed, nil, true, false}")
  end

  feature "conditional binding with params dispatches only once enabled",
          %{session: session} do
    session
    |> visit(DisabledBindingPage)
    |> click(css("#conditional_with_params"))
    |> click(css("#enable"))
    |> assert_text(css("#result"), "{nil, nil, true, false}")
    |> click(css("#conditional_with_params"))
    |> assert_text(css("#result"), "{nil, 1, true, false}")
  end

  feature "disabled binding leaves the native default behavior untouched",
          %{session: session} do
    session
    |> visit(DisabledBindingPage)
    |> click(css("#checkbox"))
    |> assert_has(css("#checkbox:checked"))
    |> click(css("#enable"))
    |> assert_text(css("#result"), "{nil, nil, true, false}")
  end
end
