defmodule HologramFeatureTests.CommandsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.Commands.LateReplyDestinationPage
  alias HologramFeatureTests.Commands.LateReplyPage
  alias HologramFeatureTests.CommandsPage

  describe "layout command" do
    feature "triggered from layout (default target)", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='layout_command_1']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{:layout_command_1, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='layout_command_2']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{:layout_command_2, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='layout_command_3']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{:layout_command_3, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "page command" do
    feature "triggered from layout", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='page_command_1']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_command_1, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from page (default target)", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='page_command_2']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_command_2, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='page_command_3']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{:page_command_3, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "component command" do
    feature "triggered from layout", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='component_2_command_1']"))
      |> assert_text(
        css("#component_2_result"),
        ~r/\{:component_2_command_1, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='component_2_command_2']"))
      |> assert_text(
        css("#component_2_result"),
        ~r/\{:component_2_command_2, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end

    feature "triggered from component (default target)", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='component_2_command_3']"))
      |> assert_text(
        css("#component_2_result"),
        ~r/\{:component_2_command_3, %\{a: 1, b: 2, event: %\{.*page_x: [0-9]+\.[0-9]+.*\}\}\}/
      )
    end
  end

  describe "server struct mutations" do
    # Covered in preceding (layout command, page command, component command) tests:
    # feature "next_action"
  end

  # Each slow command sleeps 2 seconds before replying, and each test waits 3 after navigating, so
  # the reply lands on the page navigated to. A reply that survives and raises there surfaces as a
  # Wallaby.JSError on the first command after the sleep.
  describe "reply after navigation" do
    # Positive control for the drops below: the same button's reply lands when the user stays put,
    # proving the fixture sends a real command whose reply arrives.
    feature "a slow command's reply lands when the user stays on the page", %{session: session} do
      session
      |> visit(LateReplyPage)
      |> click(button("Run slow component command"))
      |> assert_text(css("#component_result"), "nil")
      |> assert_text(css("#component_result"), ~s/"component_reply_ran"/)
    end

    # The component is mounted on the late reply page only, so a surviving reply targets a cid the
    # destination's registry does not hold and raises there.
    feature "navigating to another page drops the reply of a command targeting a component",
            %{session: session} do
      session
      |> visit(LateReplyPage)
      |> click(button("Run slow component command"))
      |> click(link("Destination link"))
      |> assert_page(LateReplyDestinationPage)
      |> sleep(3_000)
      |> assert_text("Late reply destination title")
    end

    # The layout cid resolves on the destination too, to a new instance of the same module, so a
    # surviving reply would not raise: it would write the destination layout's result.
    feature "navigating to another page drops the reply of a command targeting the layout",
            %{session: session} do
      session
      |> visit(LateReplyPage)
      |> click(button("Run slow layout command"))
      |> click(link("Destination link"))
      |> assert_page(LateReplyDestinationPage)
      |> sleep(3_000)
      |> assert_text(css("#layout_result"), "nil")
    end

    # The page cid resolves on the destination too, but to a module with no clause for the reply's
    # action, so a surviving reply raises there.
    feature "navigating to another page drops the reply of a command targeting the page",
            %{session: session} do
      session
      |> visit(LateReplyPage)
      |> click(button("Run slow page command"))
      |> click(link("Destination link"))
      |> assert_page(LateReplyDestinationPage)
      |> sleep(3_000)
      |> assert_text("Late reply destination title")
    end

    # Going back restores the registry from a snapshot rather than from mount data, so the reply
    # lands after a transition that reached the epoch bump down a different path.
    feature "going back to another page drops the reply of a command targeting the layout",
            %{session: session} do
      session
      |> visit(LateReplyDestinationPage)
      |> click(link("Late reply link"))
      |> assert_page(LateReplyPage)
      |> click(button("Run slow layout command"))
      |> go_back()
      |> assert_page(LateReplyDestinationPage)
      |> sleep(3_000)
      |> assert_text(css("#layout_result"), "nil")
    end
  end

  describe "command during a transition" do
    # The destination's bundle is held back, so its markup is on screen and clickable for seconds
    # before it mounts, while the registry still holds the page being left. A command clicked then
    # is held for the mount and built from the destination's registry. Sent at once, it would have
    # been built from the left page's, whose page module has no clause for it.
    feature "a command clicked on the destination before its mount runs once it has mounted",
            %{session: session} do
      session
      |> simulate_slow_page_bundle(4_000)
      |> visit(LateReplyPage)
      |> click(link("Destination link"))
      |> assert_has(css("#destination_title"))
      |> click(button("Run destination command"))
      |> assert_page(LateReplyDestinationPage)
      |> assert_text(css("#destination_result"), ~s/"destination_reply_ran"/)
    end
  end
end
