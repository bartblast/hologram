defmodule Hologram.Compiler.ModuleAttributeEvaluator do
  alias Hologram.Compiler.Context

  def evaluate(ast, %Context{module_attributes: module_attributes}) do
    bindings =
      Enum.map(module_attributes, fn {key, value} ->
        {:"hologram_module_attribute_#{key}__", value}
      end)

    replace_module_attributes(ast)
    |> Code.eval_quoted(bindings)
    |> elem(0)
  end

  defp replace_module_attributes({:@, metadata, [{name, _, _}]}) do
    {:"hologram_module_attribute_#{name}__", metadata, nil}
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
