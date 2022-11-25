defmodule HologramE2E.Test.Helpers do
  import ExUnit.Assertions, only: [assert: 1]

  alias Hologram.Compiler
  alias Wallaby.Browser

  def compile(opts \\ []) do
    Keyword.put(opts, :force, true)
    |> Compiler.compile()
  end

  def assert_page(session, page) do
    assert Browser.current_path(session) == page.route()
    session
  end
end
