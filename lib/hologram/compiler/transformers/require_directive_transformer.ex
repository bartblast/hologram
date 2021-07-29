defmodule Hologram.Compiler.RequireDirectiveTransformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.RequireDirective

  def transform([{_, _, module_segs}]) do
    module = Helpers.module(module_segs)
    %RequireDirective{module: module}
  end
end
