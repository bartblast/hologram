defmodule Hologram.Compiler.FunctionDefinitionTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer}
  alias Hologram.Compiler.IR.FunctionDefinition

  def transform(
        {def_type, _, [{name, _, params}, [do: {:__block__, _, body}]]},
        %Context{} = context
      )
      when is_list(params) do
    build_function_definition(name, params, body, def_type, context)
  end

  def transform({def_type, _, [{name, _, _}, [do: {:__block__, _, body}]]}, %Context{} = context) do
    build_function_definition(name, [], body, def_type, context)
  end

  defp build_function_definition(name, params, body, def_type, %{module: module} = context) do
    params = Helpers.transform_params(params, context)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings(params)
    body = Enum.map(body, &Transformer.transform(&1, context))
    visibility = if def_type == :def, do: :public, else: :private

    %FunctionDefinition{
      module: module,
      name: name,
      arity: arity,
      params: params,
      bindings: bindings,
      body: body,
      visibility: visibility
    }
  end
end
