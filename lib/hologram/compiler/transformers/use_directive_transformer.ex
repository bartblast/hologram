defmodule Hologram.Compiler.UseDirectiveTransformer do
  alias Hologram.Compiler.IR.UseDirective

  def transform({:use, _, [{_, _, alias_segs}]}) do
    %UseDirective{alias_segs: alias_segs, opts: []}
  end

  def transform({:use, _, [{_, _, alias_segs}, opts]}) do
    %UseDirective{alias_segs: alias_segs, opts: opts}
  end
end
