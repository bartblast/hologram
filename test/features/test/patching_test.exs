defmodule HologramFeatureTests.PatchingTest do
  # TODO: make the tests async when it's possible to set Wallaby max_wait_time per assert_has/2 or refute_has/2 call,
  # or implement custom versions of assert_has/2 and refute_has/2 functions.
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Patching.Page1
  alias HologramFeatureTests.Patching.Page2
  alias HologramFeatureTests.Patching.Page3
  alias HologramFeatureTests.Patching.Page4
  alias HologramFeatureTests.Patching.Page5

  setup do
    current_max_wait_time = Application.fetch_env!(:wallaby, :max_wait_time)
    Application.put_env(:wallaby, :max_wait_time, 3_000)

    on_exit(fn ->
      Application.put_env(:wallaby, :max_wait_time, current_max_wait_time)
    end)
  end

  describe "root element attributes patching" do
    feature "after action", %{session: session} do
      session
      |> visit(Page1)
      |> refute_has(css("html[attr_1]"))
      |> refute_has(css("html[attr_2]"))
      |> click(button("Add root elem attr 2"))
      |> refute_has(css("html[attr_1]"))
      |> assert_has(css("html[attr_2='value_2a']"))
      |> click(button("Add root elem attr 1"))
      |> assert_has(css("html[attr_1='value_1a']"))
      |> assert_has(css("html[attr_2='value_2a']"))
      |> click(button("Change root elem attr 2"))
      |> assert_has(css("html[attr_1='value_1a']"))
      |> assert_has(css("html[attr_2='value_2b']"))
      |> click(button("Change root elem attr 1"))
      |> assert_has(css("html[attr_1='value_1b']"))
      |> assert_has(css("html[attr_2='value_2b']"))
      |> click(button("Remove root elem attr 2"))
      |> assert_has(css("html[attr_1='value_1b']"))
      |> refute_has(css("html[attr_2]"))
      |> click(button("Remove root elem attr 1"))
      |> refute_has(css("html[attr_1]"))
      |> refute_has(css("html[attr_2]"))
    end

    feature "after navigation", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Add root elem attr 1"))
      |> click(button("Add root elem attr 2"))
      |> assert_has(css("html[attr_1='value_1a']"))
      |> assert_has(css("html[attr_2='value_2a']"))
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> refute_has(css("html[attr_1]"))
      |> refute_has(css("html[attr_2]"))
      |> assert_has(css("html[attr_3='value_3']"))
    end
  end

  describe "class attribute in root element patching" do
    feature "has class initially, changes to different class", %{session: session} do
      session
      |> visit(Page3)
      |> click(button("Change to class 2"))
      |> assert_has(css("html[class='my_class_2']"))
    end

    feature "has class initially, class is removed", %{session: session} do
      session
      |> visit(Page3)
      |> click(button("Remove class"))
      |> refute_has(css("html[class]"))
    end

    feature "no class initially, class is added", %{session: session} do
      session
      |> visit(Page4)
      |> click(button("Add class"))
      |> assert_has(css("html[class='my_class']"))
    end

    feature "has class after update, changes to different class", %{session: session} do
      session
      |> visit(Page3)
      |> click(button("Change to class 2"))
      |> assert_has(css("html[class='my_class_2']"))
      |> click(button("Change to class 3"))
      |> assert_has(css("html[class='my_class_3']"))
    end

    feature "has class after update, class is removed", %{session: session} do
      session
      |> visit(Page3)
      |> click(button("Change to class 2"))
      |> assert_has(css("html[class='my_class_2']"))
      |> click(button("Remove class"))
      |> refute_has(css("html[class]"))
    end

    feature "no class after update, class is added", %{session: session} do
      session
      |> visit(Page3)
      |> click(button("Remove class"))
      |> refute_has(css("html[class]"))
      |> click(button("Change to class 2"))
      |> assert_has(css("html[class='my_class_2']"))
    end
  end

  describe "form elements value patching" do
    feature "text input value patching", %{session: session} do
      # We're testing different combinations of specific user operations:
      # 1) change programmatically to a non-empty value that is the same as the last programmatic value
      # 2) change programmatically to a non-empty value that is different than the last programmatic value
      # 3) change programmatically to an empty value when the last programmatic value was also empty
      # 4) change programmatically to an empty value when the last programmatic value was not empty
      # 5) change manually to a non-empty value that is the same as the last programmatic value
      # 6) change manually to a non-empty value that is different than the last programmatic value
      # 7) change manually to an empty value when the last programmatic value was also empty
      # 8) change manually to an empty value when the last programmatic value was not empty

      session
      |> visit(Page5)
      |> assert_input_value("#text_input", "initial text")
      |> refute_has(css("#text_input[value]"))
      # --- Setup A: establish baseline programmatic value
      |> click(button("Update Text 1"))
      |> assert_input_value("#text_input", "programmatic 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 1 (Cond 6): change manually to a non-empty value that is different than the last programmatic value
      |> fill_in(css("#text_input"), with: "manual 1")
      |> assert_input_value("#text_input", "manual 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 2 (Cond 1): change programmatically to a non-empty value that is the same as the last programmatic value
      |> click(button("Update Text 1"))
      |> assert_input_value("#text_input", "programmatic 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 3 (Cond 2): change programmatically to a non-empty value that is different than the last programmatic value
      |> click(button("Update Text 2"))
      |> assert_input_value("#text_input", "programmatic 2")
      |> refute_has(css("#text_input[value]"))
      # --- Setup B: switch to a different manual value
      |> fill_in(css("#text_input"), with: "manual 2")
      |> assert_input_value("#text_input", "manual 2")
      |> refute_has(css("#text_input[value]"))
      # --- Group 4 (Cond 5): change manually to a non-empty value that is the same as the last programmatic value
      |> fill_in(css("#text_input"), with: "programmatic 2")
      |> assert_input_value("#text_input", "programmatic 2")
      |> refute_has(css("#text_input[value]"))
      # --- Group 5 (Cond 4): change programmatically to an empty value when the last programmatic value was not empty
      |> click(button("Clear State"))
      |> assert_input_value("#text_input", "")
      |> refute_has(css("#text_input[value]"))
      # --- Setup C: switch to a different manual value
      |> fill_in(css("#text_input"), with: "manual 3")
      |> assert_input_value("#text_input", "manual 3")
      |> refute_has(css("#text_input[value]"))
      # --- Group 6 (Cond 7): change manually to an empty value when the last programmatic value was also empty
      |> fill_in(css("#text_input"), with: "")
      |> assert_input_value("#text_input", "")
      |> refute_has(css("#text_input[value]"))
      # --- Setup D: switch to a different manual value
      |> fill_in(css("#text_input"), with: "manual 4")
      |> assert_input_value("#text_input", "manual 4")
      |> refute_has(css("#text_input[value]"))
      # --- Group 7 (Cond 3): change programmatically to an empty value when the last programmatic value was also empty
      |> click(button("Clear State"))
      |> assert_input_value("#text_input", "")
      |> refute_has(css("#text_input[value]"))
      # --- Setup E: set non-empty programmatic value
      |> click(button("Update Text 1"))
      |> assert_input_value("#text_input", "programmatic 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 8 (Cond 8): change manually to an empty value when the last programmatic value was not empty
      |> fill_in(css("#text_input"), with: "")
      |> assert_input_value("#text_input", "")
      |> refute_has(css("#text_input[value]"))
    end

    feature "email input value patching", %{session: session} do
      session
      |> visit(Page5)
      |> refute_has(css("#email_input[value]"))
      |> assert_input_value("#email_input", "initial email")
      |> click(button("Update Email 1"))
      |> refute_has(css("#email_input[value]"))
      |> assert_input_value("#email_input", "updated email 1")
      |> fill_in(css("#email_input"), with: "filled email")
      |> refute_has(css("#email_input[value]"))
      |> assert_input_value("#email_input", "filled email")
      |> click(button("Update Email 2"))
      |> refute_has(css("#email_input[value]"))
      |> assert_input_value("#email_input", "updated email 2")
      |> click(button("Clear State"))
      |> refute_has(css("#email_input[value]"))
      |> assert_input_value("#email_input", "")
    end
  end
end
