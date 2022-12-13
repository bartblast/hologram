defmodule Hologram.Compiler.CallTransformer do
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.Helpers
  alias Hologram.Compiler.IR.Call
  alias Hologram.Compiler.Transformer

  def transform(
        {{:., _, [{:__aliases__, _, alias_segs}, name]}, _, args},
        %Context{} = context
      ) do
    build_call(name, args, context, alias_segs: alias_segs)
  end

  def transform({{:., _, [Kernel, :to_string]}, _, args}, %Context{} = context) do
    build_call(:to_string, args, context, module: Kernel)
  end

  def transform(
        {{:., _, [{:__MODULE__, _, _} = module_expression, name]}, _, args},
        %Context{} = context
      ) do
    build_call(name, args, context, module_expression: module_expression)
  end

  def transform({{:., _, [atom, name]}, _, args}, %Context{} = context) when is_atom(atom) do
    module = Helpers.erlang_module(atom)
    build_call(name, args, context, module: module)
  end

  def transform({{:., _, [module_expression, name]}, _, args}, %Context{} = context) do
    build_call(name, args, context, module_expression: module_expression)
  end

  def transform({name, _, args}, %Context{} = context) do
    build_call(name, args, context, alias_segs: [])
  end

  defp build_args(args, context) do
    args = if is_list(args), do: args, else: []
    Enum.map(args, &Transformer.transform(&1, context))
  end

  defp build_call(name, args, %Context{} = context, opts) do
    args = build_args(args, context)

    module_expression =
      if opts[:module_expression] do
        Transformer.transform(opts[:module_expression], context)
      else
        nil
      end

    %Call{
      alias_segs: opts[:alias_segs],
      module: opts[:module],
      module_expression: module_expression,
      name: name,
      args: args
    }
  end
end
