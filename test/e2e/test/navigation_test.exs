defmodule HologramE2E.NavigationTest do
  use HologramE2E.TestCase, async: false

  alias HologramE2E.Page2
  alias HologramE2E.Page5

  @page_2_action_button css("#page-2-update-text-button")
  @page_2_action_text css("#page-2-text", text: "text updated by page 2 update button")
  @page_2_back_button css("#page-2-back-button")
  @page_2_link css("#page-2-link")
  @page_2_title css("h1", text: "Page 2")
  @page_5_action_button css("#page-5-update-text-button")
  @page_5_action_text css("#page-5-text", text: "text updated by page 5 update button")
  @page_5_forward_button css("#page-5-forward-button")
  @page_5_title css("h1", text: "Page 5")

  feature "anchor", %{session: session} do
    session
    |> visit(Page5.route())
    |> click(@page_2_link)
    |> assert_page(Page2)
    |> assert_has(@page_2_title)
    |> click(@page_2_action_button)
    |> assert_has(@page_2_action_text)
  end

  feature "back button", %{session: session} do
    session
    |> visit(Page5.route())
    |> click(@page_2_link)
    |> assert_page(Page2)
    |> click(@page_2_back_button)
    |> assert_page(Page5)
    |> assert_has(@page_5_title)
    |> click(@page_5_action_button)
    |> assert_has(@page_5_action_text)
  end

  feature "forward button", %{session: session} do
    session
    |> visit(Page5.route())
    |> click(@page_2_link)
    |> assert_page(Page2)
    |> click(@page_2_back_button)
    |> click(@page_5_forward_button)
    |> assert_page(Page2)
    |> assert_has(@page_2_title)
    |> click(@page_2_action_button)
    |> assert_has(@page_2_action_text)
  end
end
