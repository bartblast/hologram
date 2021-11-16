defmodule Hologram.Compiler.Decoder do
  alias Hologram.Compiler.{ListTypeDecoder, MapTypeDecoder, ModuleTypeDecoder, TupleTypeDecoder}

  def decode(%{"type" => "atom", "value" => value}) do
    String.to_atom(value)
  end

  def decode(%{"type" => "boolean", "value" => value}) do
    value
  end

  def decode(%{"type" => "integer", "value" => value}) do
    value
  end

  def decode(%{"type" => "list"} = value) do
    ListTypeDecoder.decode(value)
  end

  def decode(%{"type" => "map"} = value) do
    MapTypeDecoder.decode(value)
  end

  def decode(%{"type" => "module"} = value) do
    ModuleTypeDecoder.decode(value)
  end

  def decode(%{"type" => "string", "value" => value}) do
    value
  end

  def decode(%{"type" => "tuple"} = value) do
    TupleTypeDecoder.decode(value)
  end
end
