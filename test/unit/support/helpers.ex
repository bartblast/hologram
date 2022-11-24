defmodule Hologram.Test.Helpers do
  alias Hologram.Compiler

  def compile(opts \\ []) do
    Keyword.put(opts, :force, true)
    |> Compiler.compile()
  end

  def md5_hex_regex do
    ~r/^[0-9a-f]{32}$/
  end
end
