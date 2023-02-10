defmodule Hologram.Compiler.DotOperatorTransformer do
  alias Hologram.Compiler.AccessOperatorTransformer
  alias Hologram.Compiler.AnonymousFunctionCallTransformer
  alias Hologram.Compiler.CallTransformer
  alias Hologram.Compiler.IR.DotOperator
  alias Hologram.Compiler.Transformer

  def transform({{:., _, [Access, :get]}, _, _} = ast) do
    AccessOperatorTransformer.transform(ast)
  end

  def transform({{:., _, [_]}, _, _} = ast) do
    AnonymousFunctionCallTransformer.transform(ast)
  end

  def transform({{:., _, [left, right]}, [no_parens: true, line: _], []}) do
    %DotOperator{
      left: Transformer.transform(left),
      right: Transformer.transform(right)
    }
  end

  def transform({{:., _, _}, _, _} = ast) do
    CallTransformer.transform(ast)
  end
end
