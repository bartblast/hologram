defmodule Hologram.Compiler.Parser do
  use Hologram.Commons.Parser

  def parse(str) do
    Code.string_to_quoted(str)
  end
end
