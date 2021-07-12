defmodule Hologram.Compiler.TupleTypeTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.TupleType

  def transform(ast, %Context{} = context) when is_tuple(ast) do
    Tuple.to_list(ast)
    |> build_tuple(context)
  end

  def transform(ast, %Context{} = context), do: build_tuple(ast, context)

  defp build_tuple(list, context) do
    data = Enum.map(list, &Transformer.transform(&1, context))
    %TupleType{data: data}
  end
end
