defmodule Hologram.Compiler.MacroDefinitionTransformer do
  import Hologram.Compiler.FunctionDefinitionTransformer, only: [transform_params: 2]

  alias Hologram.Compiler.{Context, Helpers, Transformer}
  alias Hologram.Compiler.IR.MacroDefinition

  def transform(ast, %Context{} = context) do
    {:defmacro, _, [{name, _, params}, [do: {:__block__, _, body}]]} = ast

    params = transform_params(params, context)
    arity = Enum.count(params)
    bindings = Helpers.aggregate_bindings(params)
    body = Enum.map(body, &Transformer.transform(&1, context))

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
