defmodule Hologram.Socket.Decoder do
  @doc """
  Decodes a term serialized by the client and pre-decoded from JSON.
  """
  @spec decode(map | String.t()) :: any
  def decode(term)

  def decode(%{"type" => "atom", "value" => value}) do
    String.to_existing_atom(value)
  end
end
