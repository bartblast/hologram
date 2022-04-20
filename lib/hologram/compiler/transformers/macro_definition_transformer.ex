defmodule Hologram.Compiler.MacroDefinitionTransformer do
  alias Hologram.Compiler.{Context, Helpers, Transformer}
  alias Hologram.Compiler.IR.MacroDefinition

  def transform(ast, %Context{} = context) do
    {:defmacro, _, [{name, _, params}, [do: body]]} = ast

    params = Helpers.transform_params(params, context)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings_from_params(params)
    body = Transformer.transform(body, context)

    %MacroDefinition{
      module: context.module,
      name: name,
      arity: arity,
      params: params,
      bindings: bindings,
      body: body
    }
  end
end
