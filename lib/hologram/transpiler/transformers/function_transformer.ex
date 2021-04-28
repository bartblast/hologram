defmodule Hologram.Transpiler.FunctionTransformer do
  alias Hologram.Transpiler.AST.Function
  alias Hologram.Transpiler.Binder
  alias Hologram.Transpiler.Transformer

  def transform(name, params, body, module, imports, aliases) do
    params =
      (if params, do: params, else: [])
      |> Enum.map(&Transformer.transform(&1, module, imports, aliases))

    arity = Enum.count(params)

    bindings = aggregate_bindings(params)
    body = Enum.map(body, &Transformer.transform(&1, module, imports, aliases))

    %Function{name: name, arity: arity, params: params, bindings: bindings, body: body}
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
