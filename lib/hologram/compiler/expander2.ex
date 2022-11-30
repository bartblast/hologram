defmodule Hologram.Compiler.Expander2 do
  @initial_context %{aliases: %{}, module_segs: []}

  def expand(ast, context \\ @initial_context)

  def expand(
        {:defmodule, meta, [{_, _, module_segs} = alias_ast, [do: {:__block__, [], exprs}]]},
        context
      ) do
    {_, _, exp_module_segs} = exp_alias_ast = expand_defmodule_alias(alias_ast, context)
    aliases = Map.put(context.aliases, module_segs, exp_module_segs)
    context = %{context | aliases: aliases, module_segs: exp_module_segs}
    exp_exprs = Enum.map(exprs, &expand(&1, context))

    {:defmodule, meta, [exp_alias_ast, [do: {:__block__, [], exp_exprs}]]}
  end

  def expand(ast, _context) do
    ast
  end

  defp expand_defmodule_alias({:__aliases__, meta, module_segs}, context) do
    {:__aliases__, meta, context.module_segs ++ module_segs}
  end
end
