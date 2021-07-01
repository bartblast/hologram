defmodule Hologram.Compiler.Processor do
  alias Hologram.Compiler.{Helpers, Normalizer, Parser, Transformer}
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Template.VirtualDOM
  alias Hologram.Template.VirtualDOM.{Component, ElementNode, TextNode}
  alias Hologram.Typespecs, as: T

  @doc """
  Creates the module definitions map of modules used by the given module.
  """
  @spec compile(T.module_segments, map()) :: T.modules_map

  def compile(module_segments, acc \\ %{}) do
    module_definition = get_module_definition(module_segments)

    acc
    |> Map.put(module_segments, module_definition)
    |> include_imported_modules(module_definition)
    |> include_aliased_modules(module_definition)
    |> include_components(module_definition)
  end

  defp find_components(module) do
    Helpers.fully_qualified_module(module)
    |> VirtualDOM.build()
    |> find_nested_components()
    |> Enum.concat([module])
    |> Enum.uniq()
  end

  defp find_nested_components(nodes) when is_list(nodes) do
    Enum.reduce(nodes, [], &(&2 ++ find_nested_components(&1)))
  end

  defp find_nested_components(%Component{} = node) do
    find_components(node.module)
  end

  defp find_nested_components(%ElementNode{} = node) do
    Enum.reduce(node.children, [], &(&2 ++ find_nested_components(&1)))
  end

  defp find_nested_components(%TextNode{}), do: []

  def get_module_definition(module_segments) do
    Helpers.module_source_path(module_segments)
    |> Parser.parse_file!()
    |> Normalizer.normalize()
    |> Transformer.transform()
  end

  defp include_aliased_modules(acc, module_definition) do
    module_definition.aliases
    |> Enum.reduce(acc, &include_module(&2, &1.module))
  end

  defp include_components(acc, module_definition) do
    if is_component?(module_definition) do
      find_components(module_definition.name)
      |> Enum.reduce(acc, &include_module(&2, &1))
    else
      acc
    end
  end

  defp include_imported_modules(acc, module_definition) do
    module_definition.imports
    |> Enum.reduce(acc, &include_module(&2, &1.module))
  end

  defp include_module(acc, module) do
    if acc[module], do: acc, else: compile(module, acc)
  end

  @doc """
  Returns true if the given module has a use directive for Hologram.Component module.
  """
  @spec is_component?(%ModuleDefinition{}) :: boolean()

  defp is_component?(module_definition) do
    Enum.any?(module_definition.uses, &(&1.module == [:Hologram, :Component]))
  end
end
