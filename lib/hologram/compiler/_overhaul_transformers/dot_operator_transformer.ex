defmodule Hologram.Compiler.DotOperatorTransformer do
  alias Hologram.Compiler.AccessOperatorTransformer
  alias Hologram.Compiler.AnonymousFunctionCallTransformer
  alias Hologram.Compiler.CallTransformer
  alias Hologram.Compiler.IR.DotOperator
  alias Hologram.Compiler.Transformer

  def transform({{:., _, _}, _, _} = ast) do
    CallTransformer.transform(ast)
  end
end
