defmodule Hologram.Compiler.ImportDirectiveTransformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.ImportDirective

  def transform({:import, _, [{:__aliases__, _, module_segs}, opts]}) do
    only = if opts[:only], do: opts[:only], else: []
    build_import(module_segs, only)
  end

  def transform({:import, _, [{:__aliases__, _, module_segs}]}) do
    build_import(module_segs, [])
  end

  defp build_import(module_segs, only) do
    module = Helpers.module(module_segs)
    %ImportDirective{module: module, only: only}
  end
end
