defmodule Hologram.Compiler.FunctionDefinitionTransformer do
  alias Hologram.Compiler.{Binder, Context, Transformer}
  alias Hologram.Compiler.IR.FunctionDefinition

  def transform({:def, _, [{name, _, params}, [do: {:__block__, _, body}]]}, %Context{} = context) when is_list(params) do
    build_function_definition(name, params, body, context)
  end

  def transform({:def, _, [{name, _, _}, [do: {:__block__, _, body}]]}, %Context{} = context) do
    build_function_definition(name, [], body, context)
  end

  defp build_function_definition(name, params, body, context) do
    params = Helpers.transform_params(params, context)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings(params)
    body = Enum.map(body, &Transformer.transform(&1, context))

    %FunctionDefinition{name: name, arity: arity, params: params, bindings: bindings, body: body}
  end
end
