defmodule Hologram.Compiler.ImportTransformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.Import

  def transform([{:__aliases__, _, module_segs}, [only: only]]) do
    build_import(module_segs, only)
  end

  def transform([{:__aliases__, _, module_segs}]) do
    build_import(module_segs, [])
  end

  defp build_import(module_segs, only) do
    module = Helpers.module(module_segs)
    %Import{module: module, only: only}
  end
end
