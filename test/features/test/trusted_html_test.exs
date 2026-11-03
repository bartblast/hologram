defmodule HologramFeatureTests.TrustedHtmlTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Router.Helpers, as: RouterHelpers
  alias HologramFeatureTests.TrustedHtml.Page1
  alias HologramFeatureTests.TrustedHtml.Page2
  alias HologramFeatureTests.TrustedHtml.Page3
  alias HologramFeatureTests.TrustedHtml.Page4
  alias HologramFeatureTestsWeb.Endpoint

  @no_warnings "return window.trustedHtmlWarnings.length === 0;"

  # The range comments follow the content directly, so the exact match shows the script is gone.
  test "the server renders trusted HTML into the page, normalized and without its scripts" do
    conn =
      :get
      |> Plug.Test.conn(RouterHelpers.page_path(Page1))
      |> Endpoint.call(Endpoint.init([]))

    assert conn.resp_body =~
             ~s(<div id="content"><!--hologram-html--><p class="trusted">Hello <strong>world</strong></p><!--/hologram-html--></div>)

    assert conn.resp_body =~
             ~s(<div id="malformed"><!--hologram-html--><div class="unclosed"><em>open</em></div><!--/hologram-html--></div>)

    assert conn.resp_body =~
             ~s(<table id="direct_table"><!--hologram-html--><tbody><tr><td>direct row 1</td></tr></tbody><!--/hologram-html--></table>)
  end

  feature "renders trusted HTML as markup, without its scripts", %{session: session} do
    session
    |> visit(Page1)
    |> assert_text(css("#content p.trusted strong"), "world")
    |> assert_script_result("return document.querySelector('#content script') === null;", true)
    |> assert_script_result(@no_warnings, true)
  end

  feature "keeps malformed trusted HTML to its place", %{session: session} do
    session
    |> visit(Page1)
    |> assert_text(css("#malformed > div.unclosed > em"), "open")
    |> assert_text(css("#malformed + p#after_malformed"), "after")
    |> assert_script_result(@no_warnings, true)
  end

  feature "renders trusted table rows inside the table", %{session: session} do
    session
    |> visit(Page1)
    |> assert_text(css("#rows_table > tbody#rows > tr > td"), "row 1")
    |> assert_text(css("#direct_table > tbody > tr > td"), "direct row 1")
    |> assert_script_result(@no_warnings, true)
  end

  feature "an action replaces trusted HTML, without its scripts", %{session: session} do
    session
    |> visit(Page1)
    |> click(button("Replace content"))
    |> assert_text(css("#content p.replaced em"), "content")
    |> refute_has(css("#content p.trusted"))
    |> assert_script_result("return document.querySelector('#content script') === null;", true)
  end

  feature "an action replaces trusted table rows", %{session: session} do
    session
    |> visit(Page1)
    |> click(button("Add row"))
    |> assert_text(css("#rows > tr:nth-child(2) > td"), "row 2")
    |> assert_has(css("#rows > tr", count: 2))
  end

  feature "an action replaces trusted table rows placed directly in a table", %{session: session} do
    session
    |> visit(Page1)
    |> click(button("Add direct row"))
    |> assert_text(css("#direct_table > tbody > tr:nth-child(2) > td"), "direct row 2")
    |> assert_has(css("#direct_table > tbody > tr", count: 2))
    |> refute_has(css("#direct_table > tr"))
  end

  feature "renders trusted HTML on a page navigated to, without its scripts", %{session: session} do
    session
    |> visit(Page1)
    |> click(link("Page 2 link"))
    |> assert_page(Page2)
    |> assert_text(css("#content p.navigated b"), "page")
    |> assert_script_result("return document.querySelector('#content script') === null;", true)
  end

  # The browser caps the console entry an uncaught error writes, eliding the message well before
  # the page module's name ends, so only the start of the message is matched.
  feature "raises when the browser moves trusted HTML out of place", %{session: session} do
    assert_js_error(session, "trusted HTML rendered in HologramFeatureTests", fn ->
      visit(session, Page3)
    end)
  end

  feature "keeps trusted HTML something else changed before Hologram started, and warns", %{
    session: session
  } do
    warned = """
    return window.trustedHtmlWarnings.length === 1 &&
      window.trustedHtmlWarnings[0].startsWith(
        "Hologram: the page's nodes for trusted HTML rendered in HologramFeatureTests.TrustedHtml.Page4 differ"
      );
    """

    session
    |> visit(Page4)
    |> assert_text(css("#content b"), "changed")
    |> assert_script_result(warned, true)
    |> click(button("Replace content"))
    |> assert_text(css("#content i"), "replaced")
    |> refute_has(css("#content b"))
  end
end
