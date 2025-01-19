defmodule HologramFeatureTests.PatchingTest do
  # TODO: make the tests async when it's possible to set Wallaby max_wait_time per assert_has/2 or refute_has/2 call,
  # or implement custom versions of assert_has/2 and refute_has/2 functions.
  use HologramFeatureTests.TestCase, async: false

  alias HologramFeatureTests.Patching.Page1
  alias HologramFeatureTests.Patching.Page2

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
end
