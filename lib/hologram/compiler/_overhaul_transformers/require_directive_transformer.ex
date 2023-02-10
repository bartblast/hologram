defmodule Hologram.Compiler.RequireDirectiveTransformer do
  alias Hologram.Compiler.IR.RequireDirective

  def transform({:require, _, [{_, _, alias_segs}]}) do
    %RequireDirective{alias_segs: alias_segs}
  end
end
