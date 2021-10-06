defmodule Hologram.Compiler.Decoder do
  alias Hologram.Compiler.{ListTypeDecoder, MapTypeDecoder, ModuleTypeDecoder, TupleTypeDecoder}

  def decode(%{"type" => "atom", "value" => value}) do
    String.to_atom(value)
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

  def decode(%{"type" => "module", "className" => class_name}) do
    ModuleTypeDecoder.decode(class_name)
  end

  def decode(%{"type" => "string", "value" => value}) do
    value
  end

  def decode(%{"type" => "tuple", "data" => data}) do
    TupleTypeDecoder.decode(data)
  end
end
