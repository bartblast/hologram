defmodule Hologram.Compiler.TupleTypeTransformer do
  alias Hologram.Compiler.{Context, Transformer}
  alias Hologram.Compiler.IR.TupleType

  def transform({:{}, _, data}, %Context{} = context) do
    build_tuple(data, context)
  end

  def transform(data, %Context{} = context) do
    Tuple.to_list(data)
    |> build_tuple(context)
  end

  defp build_tuple(data, context) do
    data = Enum.map(data, &Transformer.transform(&1, context))
    %TupleType{data: data}
  end
end
