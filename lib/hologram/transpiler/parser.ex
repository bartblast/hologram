defmodule Hologram.Transpiler.Parser do
  use Hologram.Parser

  def parse(str) do
    Code.string_to_quoted(str)
  end
end
