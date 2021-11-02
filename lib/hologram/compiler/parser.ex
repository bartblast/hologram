defmodule Hologram.Compiler.Parser do
  use Hologram.Commons.Parser
  
  @impl Hologram.Commons.Parser
  def parse(code) do
    Code.string_to_quoted(code)
  end
end
