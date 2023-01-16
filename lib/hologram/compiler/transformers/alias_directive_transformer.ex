defmodule Hologram.Compiler.AliasDirectiveTransformer do
  alias Hologram.Compiler.IR.AliasDirective

  def transform({:alias, _, [{{_, _, [{_, _, alias_segs}, _]}, _, aliases}, _]}) do
    transform_multi_alias(alias_segs, aliases)
  end

  def transform({:alias, _, [{{_, _, [{_, _, alias_segs}, _]}, _, aliases}]}) do
    transform_multi_alias(alias_segs, aliases)
  end

  def transform({:alias, _, [{_, _, alias_segs}]}) do
    %AliasDirective{alias_segs: alias_segs, as: [List.last(alias_segs)]}
  end

  def transform({:alias, _, [{_, _, alias_segs}, opts]}) do
    as =
      if Keyword.has_key?(opts, :as) do
        elem(opts[:as], 2)
      else
        [List.last(alias_segs)]
      end

    %AliasDirective{alias_segs: alias_segs, as: as}
  end

  defp transform_multi_alias(alias_segs, aliases) do
    Enum.map(aliases, fn {:__aliases__, _, as} ->
      %AliasDirective{alias_segs: alias_segs ++ as, as: as}
    end)
  end
end
