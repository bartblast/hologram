defmodule HologramFeatureTests.PatchingTest do
  # TODO: make the tests async when it's possible to set Wallaby max_wait_time per assert_has/2 or refute_has/2 call,
  # or implement custom versions of assert_has/2 and refute_has/2 functions.
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Patching.Page1
  alias HologramFeatureTests.Patching.Page2
  alias HologramFeatureTests.Patching.Page3
  alias HologramFeatureTests.Patching.Page4
  alias HologramFeatureTests.Patching.Page5
  alias HologramFeatureTests.Patching.Page6
  alias HologramFeatureTests.Patching.Page7
  alias HologramFeatureTests.Patching.Page8
  alias HologramFeatureTests.Patching.Page9

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

  describe "body element attributes patching" do
    feature "after action", %{session: session} do
      session
      |> visit(Page6)
      |> refute_has(css("body[attr_1]"))
      |> refute_has(css("body[attr_2]"))
      |> click(button("Add body elem attr 2"))
      |> refute_has(css("body[attr_1]"))
      |> assert_has(css("body[attr_2='value_2a']"))
      |> click(button("Add body elem attr 1"))
      |> assert_has(css("body[attr_1='value_1a']"))
      |> assert_has(css("body[attr_2='value_2a']"))
      |> click(button("Change body elem attr 2"))
      |> assert_has(css("body[attr_1='value_1a']"))
      |> assert_has(css("body[attr_2='value_2b']"))
      |> click(button("Change body elem attr 1"))
      |> assert_has(css("body[attr_1='value_1b']"))
      |> assert_has(css("body[attr_2='value_2b']"))
      |> click(button("Remove body elem attr 2"))
      |> assert_has(css("body[attr_1='value_1b']"))
      |> refute_has(css("body[attr_2]"))
      |> click(button("Remove body elem attr 1"))
      |> refute_has(css("body[attr_1]"))
      |> refute_has(css("body[attr_2]"))
    end

    feature "after navigation", %{session: session} do
      session
      |> visit(Page6)
      |> click(button("Add body elem attr 1"))
      |> click(button("Add body elem attr 2"))
      |> assert_has(css("body[attr_1='value_1a']"))
      |> assert_has(css("body[attr_2='value_2a']"))
      |> click(link("Page 7 link"))
      |> assert_page(Page7)
      |> refute_has(css("body[attr_1]"))
      |> refute_has(css("body[attr_2]"))
      |> assert_has(css("body[attr_3='value_3']"))
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

  describe "class attribute in body element patching" do
    feature "has class initially, changes to different class", %{session: session} do
      session
      |> visit(Page8)
      |> click(button("Change to class 2"))
      |> assert_has(css("body[class='my_class_2']"))
    end

    feature "has class initially, class is removed", %{session: session} do
      session
      |> visit(Page8)
      |> click(button("Remove class"))
      |> refute_has(css("body[class]"))
    end

    feature "no class initially, class is added", %{session: session} do
      session
      |> visit(Page9)
      |> click(button("Add class"))
      |> assert_has(css("body[class='my_class']"))
    end

    feature "has class after update, changes to different class", %{session: session} do
      session
      |> visit(Page8)
      |> click(button("Change to class 2"))
      |> assert_has(css("body[class='my_class_2']"))
      |> click(button("Change to class 3"))
      |> assert_has(css("body[class='my_class_3']"))
    end

    feature "has class after update, class is removed", %{session: session} do
      session
      |> visit(Page8)
      |> click(button("Change to class 2"))
      |> assert_has(css("body[class='my_class_2']"))
      |> click(button("Remove class"))
      |> refute_has(css("body[class]"))
    end

    feature "no class after update, class is added", %{session: session} do
      session
      |> visit(Page8)
      |> click(button("Remove class"))
      |> refute_has(css("body[class]"))
      |> click(button("Change to class 2"))
      |> assert_has(css("body[class='my_class_2']"))
    end
  end

  describe "form elements value patching" do
    # We're testing different combinations of specific user operations:
    # 1) change programmatically to a non-empty value that is the same as the last programmatic value
    # 2) change programmatically to a non-empty value that is different than the last programmatic value
    # 3) change programmatically to an empty value when the last programmatic value was also empty
    # 4) change programmatically to an empty value when the last programmatic value was not empty
    # 5) change manually to a non-empty value that is the same as the last programmatic value
    # 6) change manually to a non-empty value that is different than the last programmatic value
    # 7) change manually to an empty value when the last programmatic value was also empty
    # 8) change manually to an empty value when the last programmatic value was not empty

    feature "text input value patching", %{session: session} do
      session
      |> visit(Page5)
      |> assert_input_value("#text_input", "initial text")
      |> refute_has(css("#text_input[value]"))
      # --- Setup A: establish baseline programmatic value
      |> click(button("Update Text 1"))
      |> assert_input_value("#text_input", "programmatic 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 1 (Cond 6): manual non-empty, different from last prog
      |> fill_in(css("#text_input"), with: "manual 1")
      |> assert_input_value("#text_input", "manual 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 2 (Cond 1): prog non-empty, same as last prog
      |> click(button("Update Text 1"))
      |> assert_input_value("#text_input", "programmatic 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 3 (Cond 2): prog non-empty, different from last prog
      |> click(button("Update Text 2"))
      |> assert_input_value("#text_input", "programmatic 2")
      |> refute_has(css("#text_input[value]"))
      # --- Setup B: switch to a different manual value
      |> fill_in(css("#text_input"), with: "manual 2")
      |> assert_input_value("#text_input", "manual 2")
      |> refute_has(css("#text_input[value]"))
      # --- Group 4 (Cond 5): manual non-empty, same as last prog
      |> fill_in(css("#text_input"), with: "programmatic 2")
      |> assert_input_value("#text_input", "programmatic 2")
      |> refute_has(css("#text_input[value]"))
      # --- Group 5 (Cond 4): prog empty, last prog was not empty
      |> click(button("Clear State"))
      |> assert_input_value("#text_input", "")
      |> refute_has(css("#text_input[value]"))
      # --- Setup C: switch to a different manual value
      |> fill_in(css("#text_input"), with: "manual 3")
      |> assert_input_value("#text_input", "manual 3")
      |> refute_has(css("#text_input[value]"))
      # --- Group 6 (Cond 7): manual empty, last prog was also empty
      |> fill_in(css("#text_input"), with: "")
      |> assert_input_value("#text_input", "")
      |> refute_has(css("#text_input[value]"))
      # --- Setup D: switch to a different manual value
      |> fill_in(css("#text_input"), with: "manual 4")
      |> assert_input_value("#text_input", "manual 4")
      |> refute_has(css("#text_input[value]"))
      # --- Group 7 (Cond 3): prog empty, last prog was also empty
      |> click(button("Clear State"))
      |> assert_input_value("#text_input", "")
      |> refute_has(css("#text_input[value]"))
      # --- Setup E: set non-empty programmatic value
      |> click(button("Update Text 1"))
      |> assert_input_value("#text_input", "programmatic 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 8 (Cond 8): manual empty, last prog was not empty
      |> fill_in(css("#text_input"), with: "")
      |> assert_input_value("#text_input", "")
      |> refute_has(css("#text_input[value]"))
    end

    feature "email input value patching", %{session: session} do
      session
      |> visit(Page5)
      |> assert_input_value("#email_input", "initial email")
      |> refute_has(css("#email_input[value]"))
      # --- Setup A: establish baseline programmatic value
      |> click(button("Update Email 1"))
      |> assert_input_value("#email_input", "programmatic 1")
      |> refute_has(css("#email_input[value]"))
      # --- Group 1 (Cond 6): manual non-empty, different from last prog
      |> fill_in(css("#email_input"), with: "manual 1")
      |> assert_input_value("#email_input", "manual 1")
      |> refute_has(css("#email_input[value]"))
      # --- Group 2 (Cond 1): prog non-empty, same as last prog
      |> click(button("Update Email 1"))
      |> assert_input_value("#email_input", "programmatic 1")
      |> refute_has(css("#email_input[value]"))
      # --- Group 3 (Cond 2): prog non-empty, different from last prog
      |> click(button("Update Email 2"))
      |> assert_input_value("#email_input", "programmatic 2")
      |> refute_has(css("#email_input[value]"))
      # --- Setup B: switch to a different manual value
      |> fill_in(css("#email_input"), with: "manual 2")
      |> assert_input_value("#email_input", "manual 2")
      |> refute_has(css("#email_input[value]"))
      # --- Group 4 (Cond 5): manual non-empty, same as last prog
      |> fill_in(css("#email_input"), with: "programmatic 2")
      |> assert_input_value("#email_input", "programmatic 2")
      |> refute_has(css("#email_input[value]"))
      # --- Group 5 (Cond 4): prog empty, last prog was not empty
      |> click(button("Clear State"))
      |> assert_input_value("#email_input", "")
      |> refute_has(css("#email_input[value]"))
      # --- Setup C: switch to a different manual value
      |> fill_in(css("#email_input"), with: "manual 3")
      |> assert_input_value("#email_input", "manual 3")
      |> refute_has(css("#email_input[value]"))
      # --- Group 6 (Cond 7): manual empty, last prog was also empty
      |> fill_in(css("#email_input"), with: "")
      |> assert_input_value("#email_input", "")
      |> refute_has(css("#email_input[value]"))
      # --- Setup D: switch to a different manual value
      |> fill_in(css("#email_input"), with: "manual 4")
      |> assert_input_value("#email_input", "manual 4")
      |> refute_has(css("#email_input[value]"))
      # --- Group 7 (Cond 3): prog empty, last prog was also empty
      |> click(button("Clear State"))
      |> assert_input_value("#email_input", "")
      |> refute_has(css("#email_input[value]"))
      # --- Setup E: set non-empty programmatic value
      |> click(button("Update Email 1"))
      |> assert_input_value("#email_input", "programmatic 1")
      |> refute_has(css("#email_input[value]"))
      # --- Group 8 (Cond 8): manual empty, last prog was not empty
      |> fill_in(css("#email_input"), with: "")
      |> assert_input_value("#email_input", "")
      |> refute_has(css("#email_input[value]"))
    end

    feature "textarea value patching", %{session: session} do
      session
      |> visit(Page5)
      |> assert_input_value("#textarea", "initial textarea")
      |> refute_has(css("#textarea[value]"))
      # --- Setup A: establish baseline programmatic value
      |> click(button("Update Textarea 1"))
      |> assert_input_value("#textarea", "programmatic 1")
      |> refute_has(css("#textarea[value]"))
      # --- Group 1 (Cond 6): manual non-empty, different from last prog
      |> fill_in(css("#textarea"), with: "manual 1")
      |> assert_input_value("#textarea", "manual 1")
      |> refute_has(css("#textarea[value]"))
      # --- Group 2 (Cond 1): prog non-empty, same as last prog
      |> click(button("Update Textarea 1"))
      |> assert_input_value("#textarea", "programmatic 1")
      |> refute_has(css("#textarea[value]"))
      # --- Group 3 (Cond 2): prog non-empty, different from last prog
      |> click(button("Update Textarea 2"))
      |> assert_input_value("#textarea", "programmatic 2")
      |> refute_has(css("#textarea[value]"))
      # --- Setup B: switch to a different manual value
      |> fill_in(css("#textarea"), with: "manual 2")
      |> assert_input_value("#textarea", "manual 2")
      |> refute_has(css("#textarea[value]"))
      # --- Group 4 (Cond 5): manual non-empty, same as last prog
      |> fill_in(css("#textarea"), with: "programmatic 2")
      |> assert_input_value("#textarea", "programmatic 2")
      |> refute_has(css("#textarea[value]"))
      # --- Group 5 (Cond 4): prog empty, last prog was not empty
      |> click(button("Clear State"))
      |> assert_input_value("#textarea", "")
      |> refute_has(css("#textarea[value]"))
      # --- Setup C: switch to a different manual value
      |> fill_in(css("#textarea"), with: "manual 3")
      |> assert_input_value("#textarea", "manual 3")
      |> refute_has(css("#textarea[value]"))
      # --- Group 6 (Cond 7): manual empty, last prog was also empty
      |> fill_in(css("#textarea"), with: "")
      |> assert_input_value("#textarea", "")
      |> refute_has(css("#textarea[value]"))
      # --- Setup D: switch to a different manual value
      |> fill_in(css("#textarea"), with: "manual 4")
      |> assert_input_value("#textarea", "manual 4")
      |> refute_has(css("#textarea[value]"))
      # --- Group 7 (Cond 3): prog empty, last prog was also empty
      |> click(button("Clear State"))
      |> assert_input_value("#textarea", "")
      |> refute_has(css("#textarea[value]"))
      # --- Setup E: set non-empty programmatic value
      |> click(button("Update Textarea 1"))
      |> assert_input_value("#textarea", "programmatic 1")
      |> refute_has(css("#textarea[value]"))
      # --- Group 8 (Cond 8): manual empty, last prog was not empty
      |> fill_in(css("#textarea"), with: "")
      |> assert_input_value("#textarea", "")
      |> refute_has(css("#textarea[value]"))
    end

    @tag timeout: 70_000
    feature "checkbox checked patching", %{session: session} do
      # We're testing different combinations of specific user operations for checkboxes:
      # 1) change programmatically to checked when the last programmatic value was also checked
      # 2) change programmatically to checked when the last programmatic value was unchecked
      # 3) change programmatically to unchecked when the last programmatic value was also unchecked
      # 4) change programmatically to unchecked when the last programmatic value was checked
      # 5) change manually to checked when the last programmatic value was also checked
      # 6) change manually to checked when the last programmatic value was unchecked
      # 7) change manually to unchecked when the last programmatic value was also unchecked
      # 8) change manually to unchecked when the last programmatic value was checked

      # credo:disable-for-lines:58 Credo.Check.Design.DuplicatedCode
      session
      |> visit(Page5)
      |> assert_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Setup A: establish baseline programmatic state (unchecked)
      |> click(button("Uncheck Checkbox"))
      |> refute_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Group 1 (Cond 6): manual checked, different from last prog (unchecked)
      |> click(css("#checkbox"))
      |> assert_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Group 2 (Cond 3): prog unchecked, same as last prog (unchecked)
      |> click(button("Uncheck Checkbox"))
      |> refute_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Group 3 (Cond 2): prog checked, different from last prog (unchecked)
      |> click(button("Check Checkbox"))
      |> assert_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Setup B: manual change to different state (unchecked)
      |> click(css("#checkbox"))
      |> refute_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Group 4 (Cond 5): manual checked, same as last prog (checked)
      |> click(css("#checkbox"))
      |> assert_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Group 5 (Cond 1): prog checked, same as last prog (checked)
      |> click(button("Check Checkbox"))
      |> assert_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Setup C: switch to unchecked programmatically
      |> click(button("Uncheck Checkbox"))
      |> refute_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Group 6 (Cond 7): manual unchecked, same as last prog (unchecked)
      |> click(css("#checkbox"))
      |> assert_has(css("#checkbox:checked"))
      |> click(css("#checkbox"))
      |> refute_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Setup D: set programmatic state to checked for next test
      |> click(button("Check Checkbox"))
      |> assert_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Group 7 (Cond 4): prog unchecked, different from last prog (checked)
      |> click(button("Uncheck Checkbox"))
      |> refute_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Setup E: set programmatic state to checked for condition 8
      |> click(button("Check Checkbox"))
      |> assert_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
      # --- Group 8 (Cond 8): manual unchecked, different from last prog (checked)
      |> click(css("#checkbox"))
      |> refute_has(css("#checkbox:checked"))
      |> refute_has(css("#checkbox[checked]"))
    end

    @tag timeout: 80_000
    feature "radio button checked patching", %{session: session} do
      # We're testing different combinations of specific user operations for radio buttons:
      # 1) change programmatically to a non-empty value that is the same as the last programmatic value
      # 2) change programmatically to a non-empty value that is different than the last programmatic value
      # 3) change programmatically to an empty value when the last programmatic value was also empty
      # 4) change programmatically to an empty value when the last programmatic value was not empty
      # 5) change manually to a non-empty value that is the same as the last programmatic value
      # 6) change manually to a non-empty value that is different than the last programmatic value

      # credo:disable-for-lines:60 Credo.Check.Design.DuplicatedCode
      session
      |> visit(Page5)
      |> refute_has(css("#radio_option_1:checked"))
      |> assert_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Setup A: establish baseline programmatic value
      |> click(button("Select Option 1"))
      |> assert_has(css("#radio_option_1:checked"))
      |> refute_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Group 1 (Cond 6): manual non-empty, different from last prog
      |> click(css("#radio_option_2"))
      |> refute_has(css("#radio_option_1:checked"))
      |> assert_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Group 2 (Cond 1): prog non-empty, same as last prog (option_1)
      |> click(button("Select Option 1"))
      |> assert_has(css("#radio_option_1:checked"))
      |> refute_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Group 3 (Cond 2): prog non-empty, different from last prog
      |> click(button("Select Option 2"))
      |> refute_has(css("#radio_option_1:checked"))
      |> assert_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Setup B: switch to a different manual value
      |> click(css("#radio_option_1"))
      |> assert_has(css("#radio_option_1:checked"))
      |> refute_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Group 4 (Cond 5): manual non-empty, same as last prog
      |> click(css("#radio_option_2"))
      |> refute_has(css("#radio_option_1:checked"))
      |> assert_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Group 5 (Cond 4): prog empty, last prog was not empty
      |> click(button("Reset Radio"))
      |> refute_has(css("#radio_option_1:checked"))
      |> refute_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Setup C: switch to a different manual value
      |> click(css("#radio_option_1"))
      |> assert_has(css("#radio_option_1:checked"))
      |> refute_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Group 6 (Cond 3): prog empty, last prog was also empty
      |> click(button("Reset Radio"))
      |> refute_has(css("#radio_option_1:checked"))
      |> refute_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
    end
  end
end
