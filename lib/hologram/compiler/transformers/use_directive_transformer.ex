defmodule Hologram.Compiler.UseDirectiveTransformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.UseDirective

  def transform(module_segs) do
    module = Helpers.module(module_segs)
    %UseDirective{module: module}
  end
end
