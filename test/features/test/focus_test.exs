defmodule HologramFeatureTests.FocusTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Focus.Page1
  alias HologramFeatureTests.Focus.Page2
  alias HologramFeatureTests.Focus.Page3
  alias HologramFeatureTests.Focus.Page4
  alias HologramFeatureTests.Focus.Page5
  alias HologramFeatureTests.Focus.Page6
  alias HologramFeatureTests.Focus.Page7

  # Focus moves in the render that follows an action, a moment after the click that dispatched it,
  # and Wallaby's own assertions only retry queries, so the active element is polled, for as long
  # as every other wait in the suite.
  defp assert_active_element(session, expected, start_time \\ nil) do
    start_time = start_time || System.monotonic_time(:millisecond)

    actual =
      script_result(session, """
      const element = document.activeElement;
      return element === document.body ? "body" : element.id;
      """)

    cond do
      actual == expected ->
        session

      System.monotonic_time(:millisecond) - start_time < max_wait_time() ->
        session
        |> sleep(50)
        |> assert_active_element(expected, start_time)

      true ->
        raise Wallaby.ExpectationNotMetError,
              "Expected the active element to be #{inspect(expected)}, but it was #{inspect(actual)}"
    end
  end

  # Clicked from a script rather than by the driver, so the button never takes focus itself: any
  # focus change that follows is then the page's doing, which is the thing under test.
  defp click_by_script(session, id) do
    execute_script(session, ~s|document.getElementById("#{id}").click();|)
  end

  defp focus_by_script(session, id) do
    execute_script(session, ~s|document.getElementById("#{id}").focus();|)
  end

  defp max_wait_time do
    Application.get_env(:wallaby, :max_wait_time, 3_000)
  end

  describe "state-driven focus" do
    feature "moves focus to the element the state names", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Focus email"))
      |> assert_active_element("page_1_email")
      |> click(button("Focus password"))
      |> assert_active_element("page_1_password")
    end

    # Clicked by script, so the email field still has focus when the render that moves it runs:
    # one render gives it up and hands it to the password field.
    feature "moves focus from one element to another in one render", %{session: session} do
      session
      |> visit(Page1)
      |> click_by_script("page_1_focus_email")
      |> assert_active_element("page_1_email")
      |> click_by_script("page_1_focus_password")
      |> assert_active_element("page_1_password")
    end

    feature "takes focus away when the state stops naming the element", %{session: session} do
      session
      |> visit(Page1)
      |> click_by_script("page_1_focus_email")
      |> assert_active_element("page_1_email")
      |> click_by_script("page_1_unfocus")
      |> assert_active_element("body")
    end

    feature "an unrelated re-render doesn't pull focus back", %{session: session} do
      session
      |> visit(Page1)
      |> click_by_script("page_1_focus_sticky")
      |> assert_active_element("page_1_sticky")
      |> focus_by_script("page_1_other")
      |> click_by_script("page_1_increment")
      |> assert_text(css("#page_1_count"), "1")
      |> assert_active_element("page_1_other")
    end

    feature "the same element can be focused again after the user left it", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Focus email"))
      |> assert_active_element("page_1_email")
      |> focus_by_script("page_1_other")
      |> click(button("Focus email"))
      |> assert_active_element("page_1_email")
    end
  end

  # These click with the driver on purpose. A driver click focuses the button, and the browser
  # skips its own autofocus once something has focus, so only Hologram can move focus to the
  # inserted field. With nothing focused, the browser could honor autofocus on its own and the
  # tests would pass without the runtime.
  describe "focus on insertion" do
    feature "an inserted element declared focused takes focus", %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Edit"))
      |> assert_active_element("page_2_editor")
    end

    feature "an inserted element with autofocus takes focus", %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Show late"))
      |> assert_active_element("page_2_late")
    end

    feature "of several candidates in one render, the first in document order wins",
            %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Show order"))
      |> assert_active_element("page_2_order_early")
    end

    # A disabled button can't take focus, so it is passed over, as the browser does for autofocus.
    feature "a candidate that can't take focus is passed over", %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Show blocked"))
      |> assert_active_element("page_2_after_disabled")
    end

    feature "a field enabled and declared focused by the same render takes focus",
            %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Unlock"))
      |> assert_active_element("page_2_unlocked")
    end

    feature "of several inserted candidates, the first wins", %{session: session} do
      session
      |> visit(Page2)
      |> click(button("Show pair"))
      |> assert_active_element("page_2_first")
    end
  end

  describe "first page load" do
    feature "the server renders autofocus and the browser focuses it", %{session: session} do
      session
      |> visit(Page3)
      |> assert_has(css("#page_3_search[autofocus]"))
      |> assert_active_element("page_3_search")
    end

    feature "the boot render leaves focus where it was moved before the runtime started",
            %{session: session} do
      session
      |> visit(Page7)
      |> click_by_script("page_7_increment")
      |> assert_text(css("#page_7_count"), "1")
      |> assert_active_element("page_7_other")
    end
  end

  describe "client-side navigation" do
    feature "honors autofocus on the new page", %{session: session} do
      session
      |> visit(Page3)
      |> click(link("Page 4 link"))
      |> assert_page(Page4)
      |> assert_active_element("page_4_search")
    end

    feature "honors $focused on the new page", %{session: session} do
      session
      |> visit(Page3)
      |> click(link("Page 5 link"))
      |> assert_page(Page5)
      |> assert_active_element("page_5_search")
    end

    # The destination is on screen before its bundle arrives. Its autofocus lands as it appears,
    # which the check on the mounted page pins down: the left page is still the mounted one when
    # focus is already on the destination's field. A field the user moves to while the bundle
    # loads then keeps focus when the page mounts.
    feature "focuses the new page as it appears, not when it mounts", %{session: session} do
      session =
        session
        |> simulate_slow_page_bundle(4_000)
        |> visit(Page3)
        |> click(link("Page 4 link"))
        |> assert_text("Page 4 title")
        |> assert_active_element("page_4_search")

      assert script_result(session, "return globalThis.Hologram.mountedPage;") == inspect(Page3)

      session
      |> focus_by_script("page_4_name")
      |> assert_page(Page4)
      |> assert_active_element("page_4_name")
    end

    # Focus is moved off the field the restored page declares focused before going back, so only
    # the restore can put it there.
    feature "honors $focused when going back to a page", %{session: session} do
      session
      |> visit(Page3)
      |> click(link("Page 4 link"))
      |> assert_page(Page4)
      |> focus_by_script("page_4_name")
      |> go_back()
      |> assert_page(Page3)
      |> assert_active_element("page_3_search")
    end

    # The marker proves the field's node survived the navigation, so the blur is the arrival's
    # doing and not a side effect of the node being replaced.
    feature "starts a page that declares no focus with nothing focused", %{session: session} do
      session =
        session
        |> visit(Page6, id: 1)
        |> execute_script(~s|document.getElementById("page_6_kept").__marker = true;|)
        |> focus_by_script("page_6_kept")
        |> click_by_script("page_6_next")
        |> assert_page(Page6, id: 2)
        |> assert_active_element("body")

      assert script_result(session, ~s|return document.getElementById("page_6_kept").__marker;|) ==
               true
    end
  end
end
