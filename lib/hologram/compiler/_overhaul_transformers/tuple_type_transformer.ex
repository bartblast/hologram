defmodule Hologram.Compiler.TupleTypeTransformer do
  alias Hologram.Compiler.IR.TupleType
  alias Hologram.Compiler.Transformer

  def transform({:{}, _, data}) do
    build_tuple(data)
  end

  def transform(data) do
    data
    |> Tuple.to_list()
    |> build_tuple()
  end

  defp build_tuple(data) do
    data = Enum.map(data, &Transformer.transform/1)
    %TupleType{data: data}
  end
end
