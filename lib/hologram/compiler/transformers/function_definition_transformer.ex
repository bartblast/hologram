defmodule Hologram.Compiler.FunctionDefinitionTransformer do
  alias Hologram.Compiler.{Binder, Context, Transformer}
  alias Hologram.Compiler.IR.FunctionDefinition

  def transform(name, params, body, %Context{} = context) do
    params =
      if(params, do: params, else: [])
      |> Enum.map(&Transformer.transform(&1, context))

    arity = Enum.count(params)

    bindings = aggregate_bindings(params)
    body = Enum.map(body, &Transformer.transform(&1, context))

    %FunctionDefinition{name: name, arity: arity, params: params, bindings: bindings, body: body}
  end

  defp aggregate_bindings(params) do
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
end
