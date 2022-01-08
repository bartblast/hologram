defmodule Hologram.Compiler.Evaluator do
  def evaluate(ast, bindings) do
    bindings =
      Enum.map(bindings, fn {key, value} ->
        {:"__hologram_#{key}__", value}
      end)

    replace_module_attributes(ast)
    |> Code.eval_quoted(bindings)
    |> elem(0)
  end

  defp replace_module_attributes({:@, metadata, [{name, _, _}]}) do
    {:"__hologram_#{name}__", metadata, nil}
  end

  defp replace_module_attributes({atom, metadata, args}) do
    args = Enum.map(args, &replace_module_attributes/1)
    {atom, metadata, args}
  end

  defp replace_module_attributes(ast), do: ast
end
