defmodule Hologram.Compiler.Decoder do
  alias Hologram.Compiler.{ListTypeDecoder, MapTypeDecoder}

  def decode(%{"type" => "integer", "value" => value}) do
    value
  end

  def decode(%{"type" => "map", "data" => data}) do
    MapTypeDecoder.decode(data)
  end

  def decode(%{"type" => "string", "value" => value}) do
    value
  end
end
