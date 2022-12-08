defmodule Hologram.Compiler.UseDirectiveTransformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.UseDirective

  def transform({:use, _, [{_, _, module_segs}]}) do
    module = Helpers.module(module_segs)
    %UseDirective{module: module, opts: []}
  end

  def transform({:use, _, [{_, _, module_segs}, opts]}) do
    module = Helpers.module(module_segs)
    %UseDirective{module: module, opts: opts}
  end
end
