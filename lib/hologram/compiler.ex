defmodule Hologram.Compiler do
  alias Hologram.Compiler.{Helpers, Reflection}
  alias Hologram.Compiler.IR.{FunctionCall, FunctionDefinition, ModuleDefinition, ModuleType, TupleType}
  alias Hologram.Template
  alias Hologram.Template.VDOM.{Component, ElementNode, Expression}
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
    |> include_used_modules(module_def)
    |> include_templatables(module_def)
  end

  defp include_aliases(acc, module_def) do
    module_def.aliases
    |> Enum.reduce(acc, &maybe_include_module(&2, &1.module))
  end

  defp include_imports(acc, module_def) do
    module_def.imports
    |> Enum.reduce(acc, &maybe_include_module(&2, &1.module))
  end

  defp include_templatables(acc, %ModuleDefinition{module: module} = module_def) do
    if Reflection.templatable?(module_def) do
      acc =
        if Helpers.is_page?(module_def) do
          maybe_include_module(acc, module.layout())
        else
          acc
        end

      vdom = Template.Builder.build(module)
      traverse_template(acc, vdom)
    else
      acc
    end
  end

  defp include_used_modules(acc, module_def) do
    module_def.functions
    |> Enum.reduce(acc, &traverse_function_defs(&2, &1))
  end

  defp maybe_include_module(acc, module) do
    unless acc[module] || Reflection.standard_lib?(module) do
      compile(module, acc)
    else
      acc
    end
  end

  defp traverse_function_defs(acc, %FunctionCall{module: module}) do
    maybe_include_module(acc, module)
  end

  defp traverse_function_defs(acc, %FunctionDefinition{body: body}) do
    Enum.reduce(body, acc, &traverse_function_defs(&2, &1))
  end

  defp traverse_function_defs(acc, %ModuleType{module: module}) do
    maybe_include_module(acc, module)
  end

  # DEFER: traverse nested code blocks
  defp traverse_function_defs(acc, _), do: acc

  defp traverse_template(acc, nodes) when is_list(nodes) do
    Enum.reduce(nodes, acc, &traverse_template(&2, &1))
  end

  defp traverse_template(acc, %Component{module: module, props: props, children: children}) do
    acc = maybe_include_module(acc, module)

    acc =
      Enum.reduce(props, acc, fn {_, value}, acc ->
        traverse_template(acc, value)
      end)

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
    maybe_include_module(acc, module)
  end

  defp traverse_template(acc, %TupleType{data: data}) do
    Enum.reduce(data, acc, &traverse_template(&2, &1))
  end

  defp traverse_template(acc, _), do: acc
end
