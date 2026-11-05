defmodule HologramFeatureTests.ForeignNodesTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.ForeignNodes.Page1
  alias HologramFeatureTests.ForeignNodes.Page2

  # The nodes HologramFeatureTestsWeb.Plugs.ForeignNodes adds: at the start, in the middle and at
  # the end of the head, and at the start and the end of the body.
  @foreign_nodes [
    ~s(head > meta[name="x-tool:first"][content="1"]),
    ~s(head > meta[name="x-tool:middle"][content="1"]),
    ~s(head > meta[name="x-tool:config"][content="1"]),
    "head > style#x-tool-style",
    "head > script:not([src])",
    "body > div#x-tool-start",
    "body > div#x-tool-end"
  ]

  defp assert_foreign_nodes(session) do
    Enum.reduce(@foreign_nodes, session, fn selector, acc ->
      assert_has(acc, css(selector, visible: :any, count: 1))
    end)
  end

  feature "keeps the nodes other tools add to the head and the body", %{session: session} do
    session
    |> visit(Page1)
    |> assert_foreign_nodes()
    |> assert_has(css(~s(head > meta:first-child[name="x-tool:first"]), visible: :any))
    |> assert_has(css(~s(head > title + meta[name="x-tool:middle"]), visible: :any))
    |> assert_has(css("body > div#x-tool-start:first-child", visible: :any))
    |> assert_has(css("body > div#x-tool-end:last-child", visible: :any))
  end

  feature "doesn't take a tag another tool put first for the layout's", %{session: session} do
    session
    |> visit(Page1)
    |> assert_has(
      css(~s(head > meta[name="x-tool:first"]:first-child + meta[charset="utf-8"]),
        visible: :any
      )
    )
  end

  feature "removes Hologram's first-load scripts", %{session: session} do
    session
    |> visit(Page1)
    |> assert_script_result(
      "return Array.from(document.scripts).map((script) => script.textContent);",
      ["globalThis.xToolRan = true;"]
    )
  end

  feature "keeps the nodes other tools add across a client-side navigation", %{session: session} do
    session
    |> visit(Page1)
    |> click(link("Page 2 link"))
    |> assert_page(Page2)
    |> assert_text("Foreign nodes page 2")
    |> refute_has(css("#page-1-root"))
    |> assert_foreign_nodes()
  end

  # Back from a page that isn't Hologram's loads the document again, with the server's state, and
  # restores the state the page was left with over it.
  feature "keeps a single copy of a tag whose attributes a restored snapshot changes",
          %{session: session} do
    session
    |> visit(Page1)
    |> click(button("Switch to dark theme"))
    |> assert_has(css("#page-1-root.dark"))
    # An unload listener keeps Chrome from putting the page in its back/forward cache, so Back
    # loads the document again.
    |> execute_script("""
    window.leftDocument = true;
    window.addEventListener("unload", () => {});
    """)
    |> visit("/external")
    |> assert_text("External Page")
    |> go_back()
    |> assert_page(Page1)
    |> assert_script_result("return window.leftDocument === undefined;", true)
    |> assert_has(css("#page-1-root.dark", count: 1))
    |> refute_has(css("#page-1-root.light"))
    |> assert_foreign_nodes()
  end
end
