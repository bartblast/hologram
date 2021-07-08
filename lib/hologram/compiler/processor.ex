defmodule Hologram.Compiler.Processor do
  alias Hologram.Compiler.{Context, Helpers, Normalizer, Parser, Transformer}
  alias Hologram.Compiler.IR.ModuleDefinition
  alias Hologram.Template.Document.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Typespecs, as: T

  @doc """
  Creates the module definitions map of modules used by the given module.
  """
  @spec compile(T.module_name_segments(), map()) :: T.module_definitions_map()

  def compile(module_name_segments, acc \\ %{}) do
    definition = get_module_definition(module_name_segments)

    acc
    |> Map.put(module_name_segments, definition)
    |> include_imported_modules(definition)
    |> include_aliased_modules(definition)
    |> include_components(definition)
  end

  defp find_components(module_name_segments) do
    module = Helpers.module(module_name_segments)

    if function_exported?(module, :template, 0) do
      VirtualDOM.build(module)
      |> find_nested_components()
      |> Enum.concat([module_name_segments])
      |> Enum.uniq()
    else
      []
    end
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
  defp find_nested_components(%Expression{}), do: []

  defp find_nested_components(%TextNode{}), do: []

  @doc """
  Returns the corresponding module definition.

  ## Examples
      iex> Processor.get_module_definition([:Abc, :Bcd])
      %ModuleDefinition{module: [:Abc, :Bcd], ...}
  """
  @spec get_module_definition(T.module_name_segments()) :: %ModuleDefinition{}

  def get_module_definition(module_name_segments) do
    context = %Context{module: [], uses: [], imports: [], aliases: [], attributes: []}

    Helpers.module_source_path(module_name_segments)
    |> Parser.parse_file!()
    |> Normalizer.normalize()
    |> Transformer.transform(context)
  end

  defp include_aliased_modules(acc, module_definition) do
    module_definition.aliases
    |> Enum.reduce(acc, &include_module(&2, &1.module))
  end

  defp include_components(acc, definition) do
    if Helpers.is_page?(definition) || Helpers.is_component?(definition) do
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
end
