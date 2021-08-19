defmodule Hologram.Compiler do
  alias Hologram.Compiler.IR.{FunctionCall, ModuleDefinition, TupleType}
  alias Hologram.Compiler.Reflection
  alias Hologram.Template
  alias Hologram.Template.Document.{Component, ElementNode, Expression}
  alias Hologram.Typespecs, as: T

  @doc """
  Creates the module definitions map of modules used by the given module.
  """
  @spec compile(module(), map()) :: T.module_definitions_map()

  def compile(module, acc \\ %{}) do
    module_def = Reflection.module_definition(module)

    acc
    |> Map.put(module, module_def)
    |> include_imports(module_def)
    |> include_aliases(module_def)
    |> include_templatables(module_def)
  end

  defp include_module(acc, module) do
    if acc[module], do: acc, else: compile(module, acc)
  end

  defp include_imports(acc, module_def) do
    module_def.imports
    |> Enum.reduce(acc, &include_module(&2, &1.module))
  end

  defp include_aliases(acc, module_def) do
    module_def.aliases
    |> Enum.reduce(acc, &include_module(&2, &1.module))
  end

  defp include_templatables(acc, %ModuleDefinition{module: module} = module_def) do
    if Reflection.is_templatable?(module_def) do
      document = Template.Builder.build(module)
      traverse_template(acc, document)
    else
      acc
    end
  end

  defp traverse_template(acc, nodes) when is_list(nodes) do
    Enum.reduce(nodes, acc, &traverse_template(&2, &1))
  end

  defp traverse_template(acc, %Component{module: module, children: children}) do
    acc = include_module(acc, module)
    Enum.reduce(children, acc, &traverse_template(&2, &1))
  end

  defp traverse_template(acc, %ElementNode{attrs: attrs, children: children}) do
    acc =
      Enum.reduce(attrs, acc, fn {_, %{value: value}}, acc ->
        traverse_template(acc, value)
      end)

    Enum.reduce(children, acc, &traverse_template(&2, &1))
  end

  defp traverse_template(acc, %Expression{ir: ir}) do
    traverse_template(acc, ir)
  end

  defp traverse_template(acc, %FunctionCall{module: module}) do
    include_module(acc, module)
  end

  defp traverse_template(acc, %TupleType{data: data}) do
    Enum.reduce(data, acc, &traverse_template(&2, &1))
  end

  defp traverse_template(acc, _), do: acc
end
