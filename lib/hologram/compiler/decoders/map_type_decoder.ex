defmodule Hologram.Compiler.MapTypeDecoder do
  alias Hologram.Compiler.Decoder

  def decode(data) do
    Enum.map(data, fn {key, value} -> {decode_key(key), Decoder.decode(value)} end)
    |> Enum.into(%{})
  end

  defp decode_key(key) do
    [_, type, value] =
      ~r/~(\w+)\[(.+)\]/
      |> Regex.run(key)

    case type do
      "atom" ->
        String.to_atom(value)

      "string" ->
        value
    end
  end
end
