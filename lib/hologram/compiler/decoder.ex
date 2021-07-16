defmodule Hologram.Compiler.Decoder do
  def decode(%{"type" => "string", "value" => value}) do
    value
  end
end
