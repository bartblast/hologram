defmodule HologramFeatureTests.Events.MouseMoveTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.Events.MouseMovePage

  feature "mouse move", %{session: session} do
    coord_regex = "[1-9][0-9]*\\.[0-9]+"

    session
    |> visit(MouseMovePage)
    |> hover(css("#my_div"))
    |> move_mouse_by(10, 20)
    |> assert_text(
      css("#result"),
      ~r/%\{event: %\{client_x: #{coord_regex}, client_y: #{coord_regex}, movement_x: #{coord_regex}, movement_y: #{coord_regex}, offset_x: #{coord_regex}, offset_y: #{coord_regex}, page_x: #{coord_regex}, page_y: #{coord_regex}, screen_x: #{coord_regex}, screen_y: #{coord_regex}\}\}/
    )
  end
end
