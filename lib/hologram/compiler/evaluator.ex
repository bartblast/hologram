defmodule Hologram.Compiler.Evaluator do
  def evaluate(ast, bindings) do
    bindings =
      Enum.map(bindings, fn {key, value} ->
        {:"hologram_#{key}__", value}
      end)

    replace_module_attributes(ast)
    |> Code.eval_quoted(bindings)
    |> elem(0)
  end

  defp replace_module_attributes({:@, metadata, [{name, _, _}]}) do
    {:"hologram_#{name}__", metadata, nil}
  end

  defp replace_module_attributes(ast) when is_list(ast) do
    Enum.map(ast, &replace_module_attributes/1)
  end

  defp replace_module_attributes(ast) when is_tuple(ast) do
    Tuple.to_list(ast)
    |> Enum.map(&replace_module_attributes/1)
    |> List.to_tuple()
  end

  defp replace_module_attributes(ast), do: ast
end
