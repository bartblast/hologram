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
  Decodes the top-level term serialized by the client that has been pre-decoded from JSON.
  The term is expected to be a list in the format [version, data] where version is an integer
  and data is the serialized content to be decoded. This is the entry point for decoding,
  which then recursively uses decode/2 for nested structures.
  """
  @spec decode(list()) :: any
  def decode(list)

  def decode([version, data]) do
    decode(version, data)
  end

  @doc """
  Decodes a term serialized by the client and pre-decoded from JSON.
  """
  @spec decode(integer, map | String.t()) :: any
  def decode(version, term)

  def decode(2, "a:" <> value) do
    String.to_existing_atom(value)
  end

  def decode(_version, %{
        "type" => "anonymous_function",
        "capturedModule" => module_str,
        "capturedFunction" => function_str,
        "arity" => arity
      }) do
    module = Module.safe_concat([module_str])
    function = String.to_existing_atom(function_str)

    Function.capture(module, function, arity)
  end

  def decode(version, %{"type" => "list", "data" => data}) do
    Enum.map(data, &decode(version, &1))
  end

  def decode(_version, %{"type" => "pid", "segments" => [x, y, z]}) do
    IEx.Helpers.pid(x, y, z)
  end

  def decode(_version, %{"type" => "port", "value" => value}) do
    IEx.Helpers.port(value)
  end

  def decode(_version, %{"type" => "reference", "value" => value}) do
    IEx.Helpers.ref(value)
  end

  def decode(version, %{"type" => "tuple", "data" => data}) do
    data
    |> Enum.map(&decode(version, &1))
    |> List.to_tuple()
  end

  def decode(1, "__atom__:" <> value) do
    String.to_existing_atom(value)
  end

  def decode(1, "__binary__:" <> value) do
    value
  end

  def decode(1, %{"type" => "bitstring", "bits" => bits}) do
    BitstringUtils.from_bit_list(bits)
  end

  def decode(1, "__float__:" <> value) do
    value
    |> Float.parse()
    |> elem(0)
  end

  def decode(1, "__integer__:" <> value) do
    IntegerUtils.parse!(value)
  end

  def decode(1, %{"type" => "map", "data" => data}) do
    data
    |> Enum.map(fn [key, value] -> {decode(1, key), decode(1, value)} end)
    |> Enum.into(%{})
  end
end
