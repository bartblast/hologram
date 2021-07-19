defmodule Hologram.Compiler.ImportTransformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.Import

  def transform(module_segs, only) do
    module = Helpers.module(module_segs)
    %Import{module: module, only: only}
  end
end
