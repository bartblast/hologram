defmodule Hologram.Compiler.Processor do
  alias Hologram.Compiler.{Helpers, Normalizer, Parser, Transformer}
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Template.VirtualDOM
  alias Hologram.Template.VirtualDOM.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Typespecs, as: T

  @doc """
  Creates the module definitions map of modules used by the given module.
  """
  @spec compile(T.module_name_segments, map()) :: T.module_definitions_map

  def compile(module_name_segments, acc \\ %{}) do
    definition = get_module_definition(module_name_segments)

    acc
    |> Map.put(module_name_segments, definition)
    |> include_imported_modules(definition)
    |> include_aliased_modules(definition)
    |> include_components(definition)
  end

  defp find_components(module_name_segments) do
    Helpers.module(module_name_segments)
    |> VirtualDOM.build()
    |> find_nested_components()
    |> Enum.concat([module_name_segments])
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

  # DEFER: find modules & functions used by template expressions
  defp find_nested_components(%Expression{} = node), do: []

  defp find_nested_components(%TextNode{}), do: []

  @doc """
  Returns the corresponding module definition.

  ## Examples
      iex> Processor.get_module_definition([:Abc, :Bcd])
      %ModuleDefinition{module: [:Abc, :Bcd], ...}
  """
  @spec get_module_definition(T.module_name_segments) :: %ModuleDefinition{}

  def get_module_definition(module_name_segments) do
    Helpers.module_source_path(module_name_segments)
    |> Parser.parse_file!()
    |> Normalizer.normalize()
    |> Transformer.transform()
  end

  defp include_aliased_modules(acc, module_definition) do
    module_definition.aliases
    |> Enum.reduce(acc, &include_module(&2, &1.module))
  end

  defp include_components(acc, definition) do
    if is_page?(definition) || is_component?(definition) do
      find_components(definition.name)
      |> Enum.reduce(acc, &include_module(&2, &1))
    else
      acc
    end
  end

  defp include_imported_modules(acc, module_definition) do
    module_definition.imports
    |> Enum.reduce(acc, &include_module(&2, &1.module))
  end

  defp include_module(acc, module_name_segments) do
    if acc[module_name_segments], do: acc, else: compile(module_name_segments, acc)
  end

  @spec is_component?(%ModuleDefinition{}) :: boolean()

  defp is_component?(module_definition) do
    Helpers.uses_module?(module_definition, [:Hologram, :Component])
  end

  defp is_page?(module_definition) do
    Helpers.uses_module?(module_definition, [:Hologram, :Page])
  end
end
