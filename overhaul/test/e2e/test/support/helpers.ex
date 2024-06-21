defmodule HologramE2E.Test.Helpers do
  import Wallaby.Browser

  require Wallaby.Browser

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
end
