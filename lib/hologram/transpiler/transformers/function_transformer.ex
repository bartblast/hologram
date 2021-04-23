defmodule Hologram.Transpiler.FunctionTransformer do
  alias Hologram.Transpiler.AST.Function
  alias Hologram.Transpiler.Binder
  alias Hologram.Transpiler.Transformer

  def transform(name, params, body, module, imports, aliases) do
    params =
      (if params, do: params, else: [])
      |> Enum.map(&Transformer.transform(&1, module, imports, aliases))

    bindings = aggregate_bindings(params)
    body = Enum.map(body, &Transformer.transform(&1, module, imports, aliases))

    %Function{name: name, params: params, bindings: bindings, body: body}
  end

  defp aggregate_bindings(params) do
    Enum.map(params, fn param ->
      case Binder.bind(param) do
        [] ->
          nil

        path ->
          path
          |> hd()
      end
    end)
    |> Enum.reject(&(&1 == nil))
  end
end
