defmodule Hologram.Compiler.Decoder do
  alias Hologram.Compiler.MapTypeDecoder

  def decode(%{"type" => "string", "value" => value}) do
    value
  end

  def decode(%{"type" => "map", "data" => data}) do
    MapTypeDecoder.decode(data)
  end
end
