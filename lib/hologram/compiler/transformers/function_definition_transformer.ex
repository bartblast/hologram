defmodule Hologram.Compiler.FunctionDefinitionTransformer do
  alias Hologram.Compiler.{Helpers, Transformer}
  alias Hologram.Compiler.IR.{FunctionDefinition, FunctionHead}

  def transform({def_type, _, [{name, _, params}, [do: body]]})
      when is_list(params) do
    build_function_definition(name, params, body, def_type)
  end

  def transform({def_type, _, [{name, _, _}, [do: body]]}) do
    build_function_definition(name, [], body, def_type)
  end

  # TODO: implement
  def transform(_) do
    %FunctionHead{}
  end

  defp build_function_definition(name, params, body, def_type) do
    params = Helpers.transform_params(params)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings_from_params(params)
    body = Transformer.transform(body)
    visibility = if def_type == :def, do: :public, else: :private

    %FunctionDefinition{
      name: name,
      arity: arity,
      params: params,
      bindings: bindings,
      body: body,
      visibility: visibility
    }
  end
end
