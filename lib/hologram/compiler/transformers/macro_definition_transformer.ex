defmodule Hologram.Compiler.MacroDefinitionTransformer do
  import Hologram.Compiler.FunctionDefinitionTransformer, only: [aggregate_bindings: 1, transform_params: 2]

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.MacroDefinition

  def transform(name, params, body, %Context{} = context) do
    params = transform_params(params, context)
    arity = Enum.count(params)
    bindings = aggregate_bindings(params)

    %MacroDefinition{name: name, arity: arity, params: params, bindings: bindings, body: body}
  end
end
