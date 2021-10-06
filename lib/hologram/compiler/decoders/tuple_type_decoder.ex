defmodule Hologram.Compiler.TupleTypeDecoder do
  alias Hologram.Compiler.Decoder

  def decode(%{"data" => data}) do
    Enum.map(data, &Decoder.decode/1)
    |> List.to_tuple()
  end
end
