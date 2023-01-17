defmodule Hologram.Compiler.Expander do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.Alias
  alias Hologram.Compiler.IR.AliasDirective
  alias Hologram.Compiler.IR.Block
  alias Hologram.Compiler.IR.IgnoredExpression
  alias Hologram.Compiler.IR.ModuleType

  def expand(ir, context \\ %Context{})

  def expand(%Alias{segments: segments}, %Context{aliases: defined_aliases} = context) do
    expanded_alias_segs = expand_alias_segs(segments, defined_aliases)
    module = Helpers.module(expanded_alias_segs)

    {%ModuleType{module: module, segments: expanded_alias_segs}, context}
  end

  def expand(
        %AliasDirective{alias_segs: alias_segs, as: as},
        %Context{aliases: defined_aliases} = context
      ) do
    expanded_alias_segs = expand_alias_segs(alias_segs, defined_aliases)
    new_defined_aliases = Map.put(defined_aliases, as, expanded_alias_segs)
    context = %{context | aliases: new_defined_aliases}

    {%IgnoredExpression{}, context}
  end

  def expand(%Block{expressions: exprs}, %Context{} = context) do
    {expanded_exprs, _new_context} =
      Enum.reduce(exprs, {[], context}, fn expr, {expanded_exprs, new_context} ->
        {expanded_expr, new_context} = expand(expr, new_context)
        {expanded_exprs ++ [expanded_expr], new_context}
      end)

    {%Block{expressions: expanded_exprs}, context}
  end

  defp expand_alias_segs([head | tail] = alias_segs, defined_aliases) do
    if defined_aliases[head] do
      defined_aliases[head] ++ tail
    else
      alias_segs
    end
  end
end
