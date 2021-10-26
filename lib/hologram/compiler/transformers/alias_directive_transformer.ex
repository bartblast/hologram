defmodule Hologram.Compiler.AliasDirectiveTransformer do
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.AliasDirective

  def transform([{{:., _, [{:__aliases__, _, module_segs}, :{}]}, _, aliases}, _]) do
    transform_multi_alias(module_segs, aliases)
  end

  def transform([{{:., _, [{:__aliases__, _, module_segs}, :{}]}, _, aliases}]) do
    transform_multi_alias(module_segs, aliases)
  end

  def transform([{_, _, module_segs}]) do
    module = Helpers.module(module_segs)
    %AliasDirective{module: module, as: [List.last(module_segs)]}
  end

  def transform([{_, _, module_segs}, opts]) do
    module = Helpers.module(module_segs)

    as =
      if Keyword.has_key?(opts, :as) do
        elem(opts[:as], 2)
      else
        [List.last(module_segs)]
      end

    %AliasDirective{module: module, as: as}
  end

  defp transform_multi_alias(module_segs, aliases) do
    Enum.map(aliases, fn {:__aliases__, _, as} ->
      module = Helpers.module(module_segs ++ as)
      %AliasDirective{module: module, as: as}
    end)
  end
end
