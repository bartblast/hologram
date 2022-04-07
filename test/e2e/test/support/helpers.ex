defmodule HologramE2E.Test.Helpers do
  alias Hologram.Compiler

  def compile(opts \\ []) do
    Keyword.put(opts, :force, true)
    |> Compiler.compile()
  end
end
