defmodule HologramFeatureTests.PatchingTest do
  # TODO: make the tests async when it's possible to set Wallaby max_wait_time per assert_has/2 or refute_has/2 call,
  # or implement custom versions of assert_has/2 and refute_has/2 functions.
  use HologramFeatureTests.TestCase, async: false

  alias HologramFeatureTests.Patching.Page1
  alias HologramFeatureTests.Patching.Page2
  alias HologramFeatureTests.Patching.Page3
  alias HologramFeatureTests.Patching.Page4

  setup do
    current_max_wait_time = Application.fetch_env!(:wallaby, :max_wait_time)
    Application.put_env(:wallaby, :max_wait_time, 3_000)

    on_exit(fn ->
      Application.put_env(:wallaby, :max_wait_time, current_max_wait_time)
    end)
  end

  feature "root element attributes patching after action", %{session: session} do
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

  feature "root element attributes patching after navigation", %{session: session} do
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
end
