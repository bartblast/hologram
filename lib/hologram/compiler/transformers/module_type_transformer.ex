defmodule Hologram.Compiler.ModuleTypeTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.ModuleType

  def transform({:__aliases__, _, alias_segs}, %Context{}) do
    %ModuleType{alias_segs: alias_segs}
  end

  def transform(alias_atom, %Context{}) do
    alias_segs = Helpers.module_name_segments(alias_atom)
    %ModuleType{alias_segs: alias_segs}
  end
end
