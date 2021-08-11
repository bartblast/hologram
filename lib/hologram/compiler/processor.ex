defmodule Hologram.Compiler.Processor do
  alias Hologram.Compiler.{Context, Helpers, Normalizer, Parser, Transformer}
  alias Hologram.Compiler.IR.{FunctionCall, ModuleDefinition, TupleType}
  alias Hologram.Template
  alias Hologram.Template.Document.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Typespecs, as: T

  @doc """
  Creates the module definitions map of modules used by the given module.
  """
  @spec compile(module(), map()) :: T.module_definitions_map()

  def compile(module, acc \\ %{}) do
    definition = get_module_definition(module)

    acc
    |> Map.put(module, definition)
    |> include_imported_modules(definition)
    |> include_aliased_modules(definition)
    |> include_pages_and_components(definition)
    |> include_modules_used_in_templates()
  end

  defp find_components(module) do
    if function_exported?(module, :template, 0) do
      Template.Builder.build(module)
      |> find_nested_components()
      |> Enum.concat([module])
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

  # DEFER: instead of matching the macro on arity, pattern match the params
  def get_macro_definition(module, name, params) do
    arity = Enum.count(params)

    get_module_definition(module).macros
    |> Enum.filter(&(&1.name == name && &1.arity == arity))
    |> hd()
  end

  def get_module_ast(module_segs) when is_list(module_segs) do
    Helpers.module(module_segs)
    |> get_module_ast()
  end

  def get_module_ast(module) do
    Helpers.module_source_path(module)
    |> Parser.parse_file!()
    |> Normalizer.normalize()
  end

  @doc """
  Returns the corresponding module definition.

  ## Examples
      iex> Processor.get_module_definition(Abc.Bcd)
      %ModuleDefinition{module: Abc.Bcd, ...}
  """
  @spec get_module_definition(module()) :: %ModuleDefinition{}

  def get_module_definition(module) do
    get_module_ast(module)
    |> Transformer.transform(%Context{})
  end

  defp include_aliased_modules(acc, module_definition) do
    module_definition.aliases
    |> Enum.reduce(acc, &include_module(&2, &1.module))
  end

  defp include_imported_modules(acc, module_definition) do
    module_definition.imports
    |> Enum.reduce(acc, &include_module(&2, &1.module))
  end

  defp include_module(acc, module) do
    if acc[module], do: acc, else: compile(module, acc)
  end

  defp include_modules_used_in_templates(acc) do
    pages = Helpers.get_pages(acc)
    components = Helpers.get_components(acc)

    (pages ++ components)
    |> Enum.reduce(acc, fn %{module: module}, acc ->
      if function_exported?(module, :template, 0) do
        Template.Builder.build(module)
        |> include_modules_used_in_templates(acc)
      else
        acc
      end
    end)
  end

  defp include_modules_used_in_templates(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, &include_modules_used_in_templates(&1, &2))
  end

  # DEFER: handle attributes and slots
  defp include_modules_used_in_templates(%Component{}, acc) do
    acc
  end

  defp include_modules_used_in_templates(%ElementNode{attrs: attrs, children: children}, acc) do
    acc =
      Enum.reduce(attrs, acc, fn {_, %{value: value}}, acc ->
        include_modules_used_in_templates(value, acc)
      end)

    Enum.reduce(children, acc, &include_modules_used_in_templates(&1, &2))
  end

  defp include_modules_used_in_templates(%Expression{ir: ir}, acc) do
    include_modules_used_in_templates(ir, acc)
  end

  defp include_modules_used_in_templates(%FunctionCall{module: module}, acc) do
    include_module(acc, module)
  end

  defp include_modules_used_in_templates(%TupleType{data: data}, acc) do
    Enum.reduce(data, acc, &include_modules_used_in_templates(&1, &2))
  end

  # DEFER: consider - this is very similar to Pruner.include_functions_used_by_templates/3
  # DEFER: implement other types
  # DEFER: consider - implement a protocol and move to separate modules
  defp include_modules_used_in_templates(%{}, acc), do: acc

  defp include_modules_used_in_templates(attr_value, acc) do
    case attr_value do
      %Expression{ir: ir} ->
        include_modules_used_in_templates(ir, acc)
      _ ->
        acc
    end
  end

  defp include_pages_and_components(acc, definition) do
    if Helpers.is_page?(definition) || Helpers.is_component?(definition) do
      find_components(definition.module)
      |> Enum.reduce(acc, &include_module(&2, &1))
    else
      acc
    end
  end
end
