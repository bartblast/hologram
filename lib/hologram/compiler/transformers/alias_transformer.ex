defmodule Hologram.Compiler.AliasTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.Alias

  def transform({:__aliases__, _, segments}, %Context{}) do
    %Alias{segments: segments}
  end

  def transform(atom, %Context{}) when is_atom(atom) do
    segments = Helpers.alias_segments(atom)
    %Alias{segments: segments}
  end
end
