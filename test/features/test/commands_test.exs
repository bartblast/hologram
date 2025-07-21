defmodule HologramFeatureTests.CommandsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.CommandsPage

  describe "layout command" do
    feature "triggered from layout (default target)", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='layout_command_1']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{"layout_command_1", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='layout_command_2']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{"layout_command_2", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='layout_command_3']"))
      |> assert_text(
        css("#layout_result"),
        ~r/\{"layout_command_3", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
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
        ~r/\{"page_command_1", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from page (default target)", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='page_command_2']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_command_2", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from component", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='page_command_3']"))
      |> assert_text(
        css("#page_result"),
        ~r/\{"page_command_3", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
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
        ~r/\{"component_2_command_1", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from page", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='component_2_command_2']"))
      |> assert_text(
        css("#component_2_result"),
        ~r/\{"component_2_command_2", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end

    feature "triggered from component (default target)", %{session: session} do
      session
      |> visit(CommandsPage)
      |> click(css("button[id='component_2_command_3']"))
      |> assert_text(
        css("#component_2_result"),
        ~r/\{"component_2_command_3", %\{a: 1, b: 2, event: %\{page_x: [0-9]+\.[0-9]+, page_y: [0-9]+\.[0-9]+\}\}\}/
      )
    end
  end

  describe "server struct mutations" do
    # Covered in preceding (layout command, page command, component command) tests:
    # feature "next_action"
  end
end
