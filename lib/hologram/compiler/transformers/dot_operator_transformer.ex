defmodule Hologram.Compiler.DotOperatorTransformer do
  alias Hologram.Compiler.AccessOperatorTransformer
  alias Hologram.Compiler.AnonymousFunctionCallTransformer
  alias Hologram.Compiler.CallTransformer
  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.DotOperator
  alias Hologram.Compiler.Transformer

  def transform({{:., _, [Access, :get]}, _, _} = ast, %Context{} = context) do
    AccessOperatorTransformer.transform(ast, context)
  end

  def transform({{:., _, [_]}, _, _} = ast, %Context{} = context) do
    AnonymousFunctionCallTransformer.transform(ast, context)
  end

  def transform({{:., _, [left, right]}, [no_parens: true, line: _], []}, %Context{} = context) do
    %DotOperator{
      left: Transformer.transform(left, context),
      right: Transformer.transform(right, context)
    }
  end

  def transform({{:., _, _}, _, _} = ast, %Context{} = context) do
    CallTransformer.transform(ast, context)
  end
end
