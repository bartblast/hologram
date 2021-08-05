defmodule Hologram.Compiler.FunctionDefinitionTransformer do
  alias Hologram.Compiler.{Binder, Context, Transformer}
  alias Hologram.Compiler.IR.FunctionDefinition

  def transform({:def, _, [{name, _, params}, [do: {:__block__, _, body}]]}, %Context{} = context) when is_list(params) do
    build_function_definition(name, params, body, context)
  end

  def transform({:def, _, [{name, _, _}, [do: {:__block__, _, body}]]}, %Context{} = context) do
    build_function_definition(name, [], body, context)
  end

  def aggregate_bindings(params) do
    Enum.with_index(params)
    |> Enum.reduce([], fn {param, idx}, acc ->
      Binder.bind(param)
      |> Enum.reduce(acc, fn binding, acc ->
        name = List.last(binding).name
        if Keyword.has_key?(acc, name), do: acc, else: Keyword.put(acc, name, {idx, binding})
      end)
    end)
    |> Enum.sort()
  end

  defp build_function_definition(name, params, body, context) do
    params = transform_params(params, context)
    arity = Enum.count(params)
    bindings = aggregate_bindings(params)
    body = Enum.map(body, &Transformer.transform(&1, context))

    %FunctionDefinition{name: name, arity: arity, params: params, bindings: bindings, body: body}
  end

  def transform_params(params, context) do
    if(params, do: params, else: [])
    |> Enum.map(&Transformer.transform(&1, context))
  end
end
