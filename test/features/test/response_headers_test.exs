defmodule HologramFeatureTests.ResponseHeadersTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ResponseHeaders.Page1
  alias HologramFeatureTests.ResponseHeaders.Page2
  alias HologramFeatureTests.ResponseHeaders.Page3
  alias HologramFeatureTests.ResponseHeaders.Page4
  alias HologramFeatureTests.ResponseHeaders.Page5
  alias HologramFeatureTestsWeb.Endpoint

  # The path a navigation to one of these pages posts to.
  @page_data_path "/hologram/page/HologramFeatureTests.ResponseHeaders"

  # A script can't read the headers of the document the browser loaded, so the request goes to the
  # endpoint directly, as a browser would send it.
  describe "first load" do
    # Plug puts a cache-control header on every response, and the one the middleware set replaces it.
    test "carries a header page middleware set, replacing the default" do
      conn =
        :get
        |> Plug.Test.conn(Page1.__route__())
        |> Endpoint.call([])

      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "cache-control") == ["no-store"]
    end

    test "carries a header the page's init/3 set" do
      conn =
        :get
        |> Plug.Test.conn(Page2.__route__())
        |> Endpoint.call([])

      assert conn.status == 200
      assert Plug.Conn.get_resp_header(conn, "x-robots-tag") == ["noindex"]
    end
  end

  # The layout records each fetch response's headers when the fetch returns, before the runtime
  # reads the body, so once the page is on screen the record is there.
  describe "navigation" do
    feature "carries a header page middleware set", %{session: session} do
      session
      |> visit(Page3)
      |> assert_text(css("#result"), "navigation origin")
      |> click(link("Page 1 link"))
      |> assert_page(Page1)
      |> assert_script_result(
        ~s(return window.__responseHeaders["#{@page_data_path}.Page1"]["cache-control"];),
        "no-store"
      )
    end

    feature "carries a header the page's init/3 set", %{session: session} do
      session
      |> visit(Page3)
      |> assert_text(css("#result"), "navigation origin")
      |> click(link("Page 2 link"))
      |> assert_page(Page2)
      |> assert_script_result(
        ~s(return window.__responseHeaders["#{@page_data_path}.Page2"]["x-robots-tag"];),
        "noindex"
      )
    end
  end

  # As with navigation, the record is there once the command's result is on screen.
  describe "command" do
    feature "carries a header the command set", %{session: session} do
      session
      |> visit(Page4)
      |> click(css("button[id='run_command']"))
      |> assert_text(css("#result"), "page 4 command ran")
      |> assert_script_result(
        ~s(return window.__responseHeaders["/hologram/command"]["x-set-by"];),
        "command"
      )
    end

    feature "carries a header command middleware set", %{session: session} do
      session
      |> visit(Page5)
      |> click(css("button[id='run_command']"))
      |> assert_text(css("#result"), "page 5 command ran")
      |> assert_script_result(
        ~s(return window.__responseHeaders["/hologram/command"]["x-set-by"];),
        "command middleware"
      )
    end
  end
end
