defmodule HologramFeatureTests.PatchingTest do
  # TODO: make the tests async when it's possible to set Wallaby max_wait_time per assert_has/2 or refute_has/2 call,
  # or implement custom versions of assert_has/2 and refute_has/2 functions.
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Patching.Page1
  alias HologramFeatureTests.Patching.Page10
  alias HologramFeatureTests.Patching.Page11
  alias HologramFeatureTests.Patching.Page12
  alias HologramFeatureTests.Patching.Page13
  alias HologramFeatureTests.Patching.Page14
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

    feature "text input value patching (without state synchronization)", %{session: session} do
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
      |> click(button("Clear All State"))
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
      |> click(button("Clear All State"))
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

    feature "text input value patching (with state synchronization)", %{session: session} do
      session
      |> visit(Page10)
      |> assert_input_value("#text_input", "initial text")
      |> assert_text(css("#text_result"), "initial text")
      |> refute_has(css("#text_input[value]"))
      # --- Setup A: establish baseline programmatic value
      |> click(button("Update Text 1"))
      |> assert_input_value("#text_input", "programmatic 1")
      |> assert_text(css("#text_result"), "programmatic 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 1 (Cond 6): manual non-empty, different from last prog
      |> fill_in(css("#text_input"), with: "manual 1")
      |> assert_input_value("#text_input", "manual 1")
      |> assert_text(css("#text_result"), "manual 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 2 (Cond 1): prog non-empty, same as last prog
      |> click(button("Update Text 1"))
      |> assert_input_value("#text_input", "programmatic 1")
      |> assert_text(css("#text_result"), "programmatic 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 3 (Cond 2): prog non-empty, different from last prog
      |> click(button("Update Text 2"))
      |> assert_input_value("#text_input", "programmatic 2")
      |> assert_text(css("#text_result"), "programmatic 2")
      |> refute_has(css("#text_input[value]"))
      # --- Setup B: switch to a different manual value
      |> fill_in(css("#text_input"), with: "manual 2")
      |> assert_input_value("#text_input", "manual 2")
      |> assert_text(css("#text_result"), "manual 2")
      |> refute_has(css("#text_input[value]"))
      # --- Group 4 (Cond 5): manual non-empty, same as last prog
      |> fill_in(css("#text_input"), with: "programmatic 2")
      |> assert_input_value("#text_input", "programmatic 2")
      |> assert_text(css("#text_result"), "programmatic 2")
      |> refute_has(css("#text_input[value]"))
      # --- Group 5 (Cond 4): prog empty, last prog was not empty
      |> click(button("Clear All State"))
      |> assert_input_value("#text_input", "")
      |> assert_text(css("#text_result"), "")
      |> refute_has(css("#text_input[value]"))
      # --- Setup C: switch to a different manual value
      |> fill_in(css("#text_input"), with: "manual 3")
      |> assert_input_value("#text_input", "manual 3")
      |> assert_text(css("#text_result"), "manual 3")
      |> refute_has(css("#text_input[value]"))
      # --- Group 6 (Cond 7): manual empty, last prog was also empty
      |> fill_in(css("#text_input"), with: "")
      |> assert_input_value("#text_input", "")
      |> assert_text(css("#text_result"), "")
      |> refute_has(css("#text_input[value]"))
      # --- Setup D: switch to a different manual value
      |> fill_in(css("#text_input"), with: "manual 4")
      |> assert_input_value("#text_input", "manual 4")
      |> assert_text(css("#text_result"), "manual 4")
      |> refute_has(css("#text_input[value]"))
      # --- Group 7 (Cond 3): prog empty, last prog was also empty
      |> click(button("Clear All State"))
      |> assert_input_value("#text_input", "")
      |> assert_text(css("#text_result"), "")
      |> refute_has(css("#text_input[value]"))
      # --- Setup E: set non-empty programmatic value
      |> click(button("Update Text 1"))
      |> assert_input_value("#text_input", "programmatic 1")
      |> assert_text(css("#text_result"), "programmatic 1")
      |> refute_has(css("#text_input[value]"))
      # --- Group 8 (Cond 8): manual empty, last prog was not empty
      |> fill_in(css("#text_input"), with: "")
      |> assert_input_value("#text_input", "")
      |> assert_text(css("#text_result"), "")
      |> refute_has(css("#text_input[value]"))
    end

    feature "email input value patching (without state synchronization)", %{session: session} do
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
      |> click(button("Clear All State"))
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
      |> click(button("Clear All State"))
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

    feature "email input value patching (with state synchronization)", %{session: session} do
      session
      |> visit(Page10)
      |> assert_input_value("#email_input", "initial email")
      |> assert_text(css("#email_result"), "initial email")
      |> refute_has(css("#email_input[value]"))
      # --- Setup A: establish baseline programmatic value
      |> click(button("Update Email 1"))
      |> assert_input_value("#email_input", "programmatic 1")
      |> assert_text(css("#email_result"), "programmatic 1")
      |> refute_has(css("#email_input[value]"))
      # --- Group 1 (Cond 6): manual non-empty, different from last prog
      |> fill_in(css("#email_input"), with: "manual 1")
      |> assert_input_value("#email_input", "manual 1")
      |> assert_text(css("#email_result"), "manual 1")
      |> refute_has(css("#email_input[value]"))
      # --- Group 2 (Cond 1): prog non-empty, same as last prog
      |> click(button("Update Email 1"))
      |> assert_input_value("#email_input", "programmatic 1")
      |> assert_text(css("#email_result"), "programmatic 1")
      |> refute_has(css("#email_input[value]"))
      # --- Group 3 (Cond 2): prog non-empty, different from last prog
      |> click(button("Update Email 2"))
      |> assert_input_value("#email_input", "programmatic 2")
      |> assert_text(css("#email_result"), "programmatic 2")
      |> refute_has(css("#email_input[value]"))
      # --- Setup B: switch to a different manual value
      |> fill_in(css("#email_input"), with: "manual 2")
      |> assert_input_value("#email_input", "manual 2")
      |> assert_text(css("#email_result"), "manual 2")
      |> refute_has(css("#email_input[value]"))
      # --- Group 4 (Cond 5): manual non-empty, same as last prog
      |> fill_in(css("#email_input"), with: "programmatic 2")
      |> assert_input_value("#email_input", "programmatic 2")
      |> assert_text(css("#email_result"), "programmatic 2")
      |> refute_has(css("#email_input[value]"))
      # --- Group 5 (Cond 4): prog empty, last prog was not empty
      |> click(button("Clear All State"))
      |> assert_input_value("#email_input", "")
      |> assert_text(css("#email_result"), "")
      |> refute_has(css("#email_input[value]"))
      # --- Setup C: switch to a different manual value
      |> fill_in(css("#email_input"), with: "manual 3")
      |> assert_input_value("#email_input", "manual 3")
      |> assert_text(css("#email_result"), "manual 3")
      |> refute_has(css("#email_input[value]"))
      # --- Group 6 (Cond 7): manual empty, last prog was also empty
      |> fill_in(css("#email_input"), with: "")
      |> assert_input_value("#email_input", "")
      |> assert_text(css("#email_result"), "")
      |> refute_has(css("#email_input[value]"))
      # --- Setup D: switch to a different manual value
      |> fill_in(css("#email_input"), with: "manual 4")
      |> assert_input_value("#email_input", "manual 4")
      |> assert_text(css("#email_result"), "manual 4")
      |> refute_has(css("#email_input[value]"))
      # --- Group 7 (Cond 3): prog empty, last prog was also empty
      |> click(button("Clear All State"))
      |> assert_input_value("#email_input", "")
      |> assert_text(css("#email_result"), "")
      |> refute_has(css("#email_input[value]"))
      # --- Setup E: set non-empty programmatic value
      |> click(button("Update Email 1"))
      |> assert_input_value("#email_input", "programmatic 1")
      |> assert_text(css("#email_result"), "programmatic 1")
      |> refute_has(css("#email_input[value]"))
      # --- Group 8 (Cond 8): manual empty, last prog was not empty
      |> fill_in(css("#email_input"), with: "")
      |> assert_input_value("#email_input", "")
      |> assert_text(css("#email_result"), "")
      |> refute_has(css("#email_input[value]"))
    end

    feature "textarea value patching (without state synchronization)", %{session: session} do
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
      |> click(button("Clear All State"))
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
      |> click(button("Clear All State"))
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

    feature "textarea value patching (with state synchronization)", %{session: session} do
      session
      |> visit(Page10)
      |> assert_input_value("#textarea", "initial textarea")
      |> assert_text(css("#textarea_result"), "initial textarea")
      |> refute_has(css("#textarea[value]"))
      # --- Setup A: establish baseline programmatic value
      |> click(button("Update Textarea 1"))
      |> assert_input_value("#textarea", "programmatic 1")
      |> assert_text(css("#textarea_result"), "programmatic 1")
      |> refute_has(css("#textarea[value]"))
      # --- Group 1 (Cond 6): manual non-empty, different from last prog
      |> fill_in(css("#textarea"), with: "manual 1")
      |> assert_input_value("#textarea", "manual 1")
      |> assert_text(css("#textarea_result"), "manual 1")
      |> refute_has(css("#textarea[value]"))
      # --- Group 2 (Cond 1): prog non-empty, same as last prog
      |> click(button("Update Textarea 1"))
      |> assert_input_value("#textarea", "programmatic 1")
      |> assert_text(css("#textarea_result"), "programmatic 1")
      |> refute_has(css("#textarea[value]"))
      # --- Group 3 (Cond 2): prog non-empty, different from last prog
      |> click(button("Update Textarea 2"))
      |> assert_input_value("#textarea", "programmatic 2")
      |> assert_text(css("#textarea_result"), "programmatic 2")
      |> refute_has(css("#textarea[value]"))
      # --- Setup B: switch to a different manual value
      |> fill_in(css("#textarea"), with: "manual 2")
      |> assert_input_value("#textarea", "manual 2")
      |> assert_text(css("#textarea_result"), "manual 2")
      |> refute_has(css("#textarea[value]"))
      # --- Group 4 (Cond 5): manual non-empty, same as last prog
      |> fill_in(css("#textarea"), with: "programmatic 2")
      |> assert_input_value("#textarea", "programmatic 2")
      |> assert_text(css("#textarea_result"), "programmatic 2")
      |> refute_has(css("#textarea[value]"))
      # --- Group 5 (Cond 4): prog empty, last prog was not empty
      |> click(button("Clear All State"))
      |> assert_input_value("#textarea", "")
      |> assert_text(css("#textarea_result"), "")
      |> refute_has(css("#textarea[value]"))
      # --- Setup C: switch to a different manual value
      |> fill_in(css("#textarea"), with: "manual 3")
      |> assert_input_value("#textarea", "manual 3")
      |> assert_text(css("#textarea_result"), "manual 3")
      |> refute_has(css("#textarea[value]"))
      # --- Group 6 (Cond 7): manual empty, last prog was also empty
      |> fill_in(css("#textarea"), with: "")
      |> assert_input_value("#textarea", "")
      |> assert_text(css("#textarea_result"), "")
      |> refute_has(css("#textarea[value]"))
      # --- Setup D: switch to a different manual value
      |> fill_in(css("#textarea"), with: "manual 4")
      |> assert_input_value("#textarea", "manual 4")
      |> assert_text(css("#textarea_result"), "manual 4")
      |> refute_has(css("#textarea[value]"))
      # --- Group 7 (Cond 3): prog empty, last prog was also empty
      |> click(button("Clear All State"))
      |> assert_input_value("#textarea", "")
      |> assert_text(css("#textarea_result"), "")
      |> refute_has(css("#textarea[value]"))
      # --- Setup E: set non-empty programmatic value
      |> click(button("Update Textarea 1"))
      |> assert_input_value("#textarea", "programmatic 1")
      |> assert_text(css("#textarea_result"), "programmatic 1")
      |> refute_has(css("#textarea[value]"))
      # --- Group 8 (Cond 8): manual empty, last prog was not empty
      |> fill_in(css("#textarea"), with: "")
      |> assert_input_value("#textarea", "")
      |> assert_text(css("#textarea_result"), "")
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

    @tag timeout: 100_000
    feature "radio checked patching", %{session: session} do
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
      |> click(button("Select Radio Option 1"))
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
      |> click(button("Select Radio Option 1"))
      |> assert_has(css("#radio_option_1:checked"))
      |> refute_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
      # --- Group 3 (Cond 2): prog non-empty, different from last prog
      |> click(button("Select Radio Option 2"))
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
      |> click(button("Clear Radio"))
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
      |> click(button("Clear Radio"))
      |> refute_has(css("#radio_option_1:checked"))
      |> refute_has(css("#radio_option_2:checked"))
      |> refute_has(css("#radio_option_1[checked]"))
      |> refute_has(css("#radio_option_2[checked]"))
    end

    @tag timeout: 100_000
    feature "select selected patching", %{session: session} do
      # We're testing different combinations of specific user operations for selects:
      # 1) change programmatically to a non-empty value that is the same as the last programmatic value
      # 2) change programmatically to a non-empty value that is different than the last programmatic value
      # 3) change programmatically to an empty value when the last programmatic value was also empty
      # 4) change programmatically to an empty value when the last programmatic value was not empty
      # 5) change manually to a non-empty value that is the same as the last programmatic value
      # 6) change manually to a non-empty value that is different than the last programmatic value

      # credo:disable-for-lines:60 Credo.Check.Design.DuplicatedCode
      session
      |> visit(Page5)
      |> assert_input_value("#select", "option_2")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
      # --- Setup A: establish baseline programmatic value
      |> click(button("Select Select Option 1"))
      |> assert_input_value("#select", "option_1")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
      # --- Group 1 (Cond 6): manual non-empty, different from last prog
      |> click(css("#select_option_2"))
      |> assert_input_value("#select", "option_2")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
      # --- Group 2 (Cond 1): prog non-empty, same as last prog (option_1)
      |> click(button("Select Select Option 1"))
      |> assert_input_value("#select", "option_1")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
      # --- Group 3 (Cond 2): prog non-empty, different from last prog
      |> click(button("Select Select Option 2"))
      |> assert_input_value("#select", "option_2")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
      # --- Setup B: switch to a different manual value
      |> click(css("#select_option_1"))
      |> assert_input_value("#select", "option_1")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
      # --- Group 4 (Cond 5): manual non-empty, same as last prog
      |> click(css("#select_option_2"))
      |> assert_input_value("#select", "option_2")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
      # --- Group 5 (Cond 4): prog empty, last prog was not empty
      |> click(button("Clear Select"))
      |> assert_input_value("#select", "")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
      # --- Setup C: switch to a different manual value
      |> click(css("#select_option_1"))
      |> assert_input_value("#select", "option_1")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
      # --- Group 6 (Cond 3): prog empty, last prog was also empty
      |> click(button("Clear Select"))
      |> assert_input_value("#select", "")
      |> refute_has(css("#select_option_1[selected]"))
      |> refute_has(css("#select_option_2[selected]"))
    end
  end

  describe "sibling identity across block boundaries" do
    feature "stateful siblings survive a conditional toggle", %{session: session} do
      inputs = ["input_a", "input_b", "input_c"]

      # Each input is tagged with a property the diff never reads, so it lives exactly as long as
      # the DOM node does. The keeper wrapper is tagged too, which is what makes it possible to see
      # a keeper repurposed into a banner rather than merely replaced.
      mark_nodes = """
      #{inspect(inputs)}.forEach((id) => {
        const input = document.getElementById(id);
        input.__probe = id;
        input.closest(".keeper").__probe = id;
      });
      document.getElementById("input_a").focus();
      """

      # Clicked from a script rather than by the driver so the button never takes focus: any focus
      # loss below is then caused by the patch, which is the thing under test.
      toggle = ~s|document.querySelector("button").click();|

      kept_nodes = """
      return #{inspect(inputs)}.filter((id) => document.getElementById(id).__probe === id);
      """

      repurposed_keepers = """
      return ["panel_a", "panel_b", "panel_c"].filter(
        (id) => document.querySelector(`#${id} .banner`).__probe !== undefined,
      );
      """

      session =
        session
        |> visit(Page11)
        |> assert_text(css("#result"), "false")
        |> fill_in(css("#input_a"), with: "typed a")
        |> fill_in(css("#input_b"), with: "typed b")
        |> fill_in(css("#input_c"), with: "typed c")

      script_result(session, mark_nodes)
      script_result(session, toggle)

      session
      |> assert_text(css("#result"), "true")
      |> assert_count(".banner", 3)
      |> assert_input_value("#input_a", "typed a")
      |> assert_input_value("#input_b", "typed b")
      |> assert_input_value("#input_c", "typed c")
      |> assert_script_result(kept_nodes, inputs)
      |> assert_script_result(repurposed_keepers, [])
      |> assert_script_result(~s|return document.activeElement.id;|, "input_a")
    end

    feature "stateful siblings survive a branch switch", %{session: session} do
      inputs = ["input_a", "input_b"]

      mark_nodes = """
      #{inspect(inputs)}.forEach((id) => {
        const input = document.getElementById(id);
        input.__probe = id;
        input.closest(".keeper").__probe = id;
      });
      document.getElementById("input_a").focus();
      """

      switch = ~s|document.querySelector("button").click();|

      kept_nodes = """
      return #{inspect(inputs)}.filter((id) => document.getElementById(id).__probe === id);
      """

      repurposed_keepers = """
      return ["panel_a", "panel_b"].filter((id) =>
        [...document.querySelectorAll(`#${id} .branch`)].some((el) => el.__probe !== undefined),
      );
      """

      session =
        session
        |> visit(Page12)
        |> assert_text(css("#result"), "true")
        |> fill_in(css("#input_a"), with: "typed a")
        |> fill_in(css("#input_b"), with: "typed b")

      script_result(session, mark_nodes)
      script_result(session, switch)

      session
      |> assert_text(css("#result"), "false")
      |> assert_input_value("#input_a", "typed a")
      |> assert_input_value("#input_b", "typed b")
      |> assert_script_result(kept_nodes, inputs)
      |> assert_script_result(repurposed_keepers, [])
      |> assert_script_result(~s|return document.activeElement.id;|, "input_a")

      script_result(session, switch)

      session
      |> assert_text(css("#result"), "true")
      |> assert_input_value("#input_a", "typed a")
      |> assert_input_value("#input_b", "typed b")
      |> assert_script_result(kept_nodes, inputs)
      |> assert_script_result(repurposed_keepers, [])
      |> assert_script_result(~s|return document.activeElement.id;|, "input_a")
    end

    feature "stateful siblings survive loop changes", %{session: session} do
      inputs = ["input_a", "input_b"]

      mark_nodes = """
      #{inspect(inputs)}.forEach((id) => {
        document.getElementById(id).__probe = id;
      });
      """

      kept_nodes = """
      return #{inspect(inputs)}.filter((id) => document.getElementById(id).__probe === id);
      """

      session =
        session
        |> visit(Page13)
        |> click(button("Add item"))
        |> click(button("Add item"))
        |> assert_text(css("#result"), "item 1, item 2, item 3")
        |> fill_in(css("#input_a"), with: "typed a")
        |> fill_in(css("#input_b"), with: "typed b")

      script_result(session, mark_nodes)

      # Switching the conditional inside the loop body renders the same marker once per item, so
      # this is the patch that throws when repeated keys reach the diff unnumbered. It takes three
      # of them: with two the diff realigns on its own and the failure does not surface.
      session
      |> click(button("Toggle badges"))
      |> assert_count(".badge", 0)
      |> assert_input_value("#input_a", "typed a")
      |> assert_input_value("#input_b", "typed b")
      |> assert_script_result(kept_nodes, inputs)
      |> click(button("Toggle badges"))
      |> assert_count(".badge", 3)
      |> assert_input_value("#input_a", "typed a")
      |> assert_input_value("#input_b", "typed b")
      |> assert_script_result(kept_nodes, inputs)

      session
      |> click(button("Add item"))
      |> assert_text(css("#result"), "item 1, item 2, item 3, item 4")
      |> assert_input_value("#input_a", "typed a")
      |> assert_input_value("#input_b", "typed b")
      |> assert_script_result(kept_nodes, inputs)
      |> click(button("Remove item"))
      |> click(button("Remove item"))
      |> assert_text(css("#result"), "item 1, item 2")
      |> assert_input_value("#input_a", "typed a")
      |> assert_input_value("#input_b", "typed b")
      |> assert_script_result(kept_nodes, inputs)
    end

    feature "stateful siblings survive several conditionals switching at once", %{
      session: session
    } do
      fields = ["field_1", "field_2", "field_3"]

      mark_nodes = """
      #{inspect(fields)}.forEach((id) => {
        document.getElementById(id).__probe = id;
      });
      """

      kept_nodes = """
      return #{inspect(fields)}.filter((id) => document.getElementById(id).__probe === id);
      """

      typed_values = """
      return #{inspect(fields)}.map((id) => document.getElementById(id).value);
      """

      session =
        session
        |> visit(Page14)
        |> assert_text(css("#result"), "true")
        |> assert_count(".hint", 3)
        |> fill_in(css("#field_1"), with: "typed 1")
        |> fill_in(css("#field_2"), with: "typed 2")
        |> fill_in(css("#field_3"), with: "typed 3")

      script_result(session, mark_nodes)

      # Hiding is the direction that fails: three regions shrink in one patch, and the fields
      # between them are keyless. Values are read as a list so a value landing in a neighbouring
      # field is caught, not just a value going missing.
      session
      |> click(button("Toggle hints"))
      |> assert_text(css("#result"), "false")
      |> assert_count(".hint", 0)
      |> assert_script_result(typed_values, ["typed 1", "typed 2", "typed 3"])
      |> assert_script_result(kept_nodes, fields)
      |> click(button("Toggle hints"))
      |> assert_text(css("#result"), "true")
      |> assert_count(".hint", 3)
      |> assert_script_result(typed_values, ["typed 1", "typed 2", "typed 3"])
      |> assert_script_result(kept_nodes, fields)
    end
  end
end
