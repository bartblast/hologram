defmodule Hologram.Compiler.ListTypeDecoder do
  alias Hologram.Compiler.Decoder

  def decode(data) do
    Enum.map(data, &Decoder.decode/1)
  end
end
