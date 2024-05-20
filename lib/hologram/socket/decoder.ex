defmodule Hologram.Socket.Decoder do
  alias Hologram.Commons.IntegerUtils

  @doc """
  Decodes a term serialized by the client and pre-decoded from JSON.
  """
  @spec decode(map | String.t()) :: any
  def decode(term)

  def decode(%{"type" => "atom", "value" => value}) do
    String.to_existing_atom(value)
  end

  def decode("__binary__:" <> value) do
    value
  end

  def decode(%{"type" => "float", "value" => value}) when is_integer(value) do
    value + 0.0
  end

  def decode(%{"type" => "float", "value" => value}) do
    value
  end

  def decode("__integer__:" <> value) do
    IntegerUtils.parse!(value)
  end
end
