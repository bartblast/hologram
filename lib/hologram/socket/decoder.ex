defmodule Hologram.Socket.Decoder do
  @moduledoc false

  alias Hologram.Commons.BitstringUtils
  alias Hologram.Commons.IntegerUtils

  # This is added only to make String.to_existing_atom/1 recognize atoms related to client DOM events
  @atoms_whitelist [
    # change event, select event
    :value,

    # mouse event, pointer event
    :page_x,
    :page_y,

    # pointer event
    :mouse,
    :pen,
    :touch,
    :pointer_type
  ]

  # Can't use control characters in 0x00-0x1F range,
  # because they are escaped in JSON and result in multi-byte delimiter  
  @delimiter "\x80"

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
  def decode(version, data)

  def decode(2, "a" <> value) do
    String.to_existing_atom(value)
  end

  def decode(2, "b"), do: ""

  def decode(2, "b0" <> <<hex::binary>>) do
    Base.decode16!(hex, case: :lower)
  end

  def decode(2, "b" <> <<leftover_bits::binary-size(1), hex::binary>>) do
    bytes = Base.decode16!(hex, case: :lower)
    leftover_bit_count = String.to_integer(leftover_bits)

    <<full_bytes::binary-size(byte_size(bytes) - 1), leftover_bits_byte::integer>> = bytes
    leftover_bits_byte = Bitwise.bsr(leftover_bits_byte, 8 - leftover_bit_count)
    <<full_bytes::binary, leftover_bits_byte::size(leftover_bit_count)>>
  end

  def decode(2, "c" <> data) do
    [module_str, function_str, arity_str] = String.split(data, @delimiter)

    module = Module.safe_concat([module_str])
    function = String.to_existing_atom(function_str)
    arity = IntegerUtils.parse!(arity_str)

    Function.capture(module, function, arity)
  end

  def decode(2, "f" <> value) do
    value
    |> Float.parse()
    |> elem(0)
  end

  def decode(2, "i" <> value) do
    IntegerUtils.parse!(value)
  end

  def decode(2, %{"t" => "l", "d" => data}) do
    Enum.map(data, &decode(2, &1))
  end

  def decode(2, %{"t" => "m", "d" => data}) do
    data
    |> Enum.map(fn [key, value] -> {decode(2, key), decode(2, value)} end)
    |> Enum.into(%{})
  end

  def decode(2, "o" <> data) do
    [_node, segments_str, _origin] = String.split(data, @delimiter)

    [major, minor] =
      segments_str
      |> String.split(",")
      |> Enum.map(&IntegerUtils.parse!/1)

    IEx.Helpers.port(major, minor)
  end

  def decode(2, "p" <> data) do
    [_node, segments_str, _origin] = String.split(data, @delimiter)

    [x, y, z] =
      segments_str
      |> String.split(",")
      |> Enum.map(&IntegerUtils.parse!/1)

    IEx.Helpers.pid(x, y, z)
  end

  def decode(2, %{"t" => "t", "d" => data}) do
    data
    |> Enum.map(&decode(2, &1))
    |> List.to_tuple()
  end

  def decode(1, "__atom__:" <> value) do
    String.to_existing_atom(value)
  end

  def decode(1, "__binary__:" <> value) do
    value
  end

  def decode(1, %{
        "type" => "anonymous_function",
        "capturedModule" => module_str,
        "capturedFunction" => function_str,
        "arity" => arity
      }) do
    module = Module.safe_concat([module_str])
    function = String.to_existing_atom(function_str)

    Function.capture(module, function, arity)
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

  def decode(1, %{"type" => "list", "data" => data}) do
    Enum.map(data, &decode(1, &1))
  end

  def decode(1, %{"type" => "map", "data" => data}) do
    data
    |> Enum.map(fn [key, value] -> {decode(1, key), decode(1, value)} end)
    |> Enum.into(%{})
  end

  def decode(1, %{"type" => "pid", "segments" => [x, y, z]}) do
    IEx.Helpers.pid(x, y, z)
  end

  def decode(1, %{"type" => "port", "value" => value}) do
    IEx.Helpers.port(value)
  end

  def decode(1, %{"type" => "reference", "value" => value}) do
    IEx.Helpers.ref(value)
  end

  def decode(1, %{"type" => "tuple", "data" => data}) do
    data
    |> Enum.map(&decode(1, &1))
    |> List.to_tuple()
  end

  @doc """
  Returns the delimiter string used for separating fields in serialized data.
  """
  @spec delimiter() :: String.t()
  def delimiter, do: @delimiter
end
