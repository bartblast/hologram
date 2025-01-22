defmodule Hologram.Socket.Decoder do
  @moduledoc false

  alias Hologram.Commons.BitstringUtils
  alias Hologram.Commons.IntegerUtils

  # This is added only to make String.to_existing_atom/1 recognize atoms related to client DOM events
  @atoms_whitelist [
    # click event
    :page_x,
    :page_y
  ]

  @doc """
  Returns the atoms whitelist related to client DOM events. 
  """
  @spec atoms_whitelist :: list(atom)
  def atoms_whitelist, do: @atoms_whitelist

  @doc """
  Decodes a term serialized by the client and pre-decoded from JSON.
  """
  @spec decode(map | String.t()) :: any
  def decode(term)

  def decode([_version, data]) do
    decode(data)
  end

  def decode(%{
        "type" => "anonymous_function",
        "capturedModule" => module_str,
        "capturedFunction" => function_str,
        "arity" => arity
      }) do
    module = Module.safe_concat([module_str])
    function = String.to_existing_atom(function_str)

    Function.capture(module, function, arity)
  end

  def decode("__atom__:" <> value) do
    String.to_existing_atom(value)
  end

  def decode("__binary__:" <> value) do
    value
  end

  def decode(%{"type" => "bitstring", "bits" => bits}) do
    BitstringUtils.from_bit_list(bits)
  end

  def decode("__float__:" <> value) do
    value
    |> Float.parse()
    |> elem(0)
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
