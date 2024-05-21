defmodule Hologram.Socket.Decoder do
  alias Hologram.Commons.BitstringUtils
  alias Hologram.Commons.IntegerUtils

  # This is added only to make String.to_existing_atom/1 recognize atoms related to client DOM events
  @atoms_whitelist [
    # click event
    :page_x,
    :page_y
  ]

  def atoms_whitelist, do: @atoms_whitelist

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

  def decode(%{"type" => "bitstring", "bits" => bits}) do
    BitstringUtils.from_bit_list(bits)
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

  def decode(%{"type" => "list", "data" => data}) do
    Enum.map(data, &decode/1)
  end

  def decode(%{"type" => "map", "data" => data}) do
    data
    |> Enum.map(fn [key, value] -> {decode(key), decode(value)} end)
    |> Enum.into(%{})
  end

  def decode(%{"type" => "pid", "segments" => [x, y, z]}) do
    IEx.Helpers.pid(x, y, z)
  end

  def decode(%{"type" => "port", "value" => value}) do
    IEx.Helpers.port(value)
  end

  def decode(%{"type" => "reference", "value" => value}) do
    IEx.Helpers.ref(value)
  end

  def decode(%{"type" => "tuple", "data" => data}) do
    data
    |> Enum.map(&decode/1)
    |> List.to_tuple()
  end
end
