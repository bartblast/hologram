defmodule HologramE2E.Test.Helpers do
  require Wallaby.Browser
  import ExUnit.Assertions, only: [assert: 1]

  alias Hologram.Compiler
  alias Wallaby.Browser

  def click(session, query) do
    session
    |> Browser.assert_has(query)
    |> Browser.click(query)
  end

  def compile(opts \\ []) do
    Keyword.put(opts, :force, true)
    |> Compiler.compile()
  end

  def assert_page(session, page) do
    assert Browser.current_path(session) == page.route()
    session
  end

  def visit(session, page) do
    Browser.visit(session, page.route())
  end
end
