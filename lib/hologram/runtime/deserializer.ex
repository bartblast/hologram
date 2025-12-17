defmodule Hologram.Runtime.Deserializer do
  @moduledoc false

  alias Hologram.Commons.BitstringUtils
  alias Hologram.Commons.IntegerUtils

  # This is added only to make String.to_existing_atom/1 recognize atoms related to client DOM events
  @atoms_whitelist [
    # change event, select event
    :value,

    # mouse event, mouse move event, pointer event
    :page_x,
    :page_y,

    # mouse move event
    :client_x,
    :client_y,
    :movement_x,
    :movement_y,
    :offset_x,
    :offset_y,
    :screen_x,
    :screen_y,

    # pointer event
    :mouse,
    :pen,
    :touch,
    :pointer_type
  ]

  # Can't use control characters in 0x00-0x1F (0-31) range
  # because they are escaped in JSON and result in multi-byte delimiter.
  # Can't use characters above 0x7F (128) because they mess up transmission encoding.
  # Using \x7F (DEL character) which is practically unused.
  @delimiter "\x7F"

  @doc """
  Returns the atoms whitelist related to client DOM events. 
  """
  @spec atoms_whitelist :: list(atom)
  def atoms_whitelist, do: @atoms_whitelist

  @doc """
  Deserializes the top-level term serialized by the client in Hologram format into Elixir terms.

  The input can be either:
  - A binary containing raw JSON that will be parsed first, then deserialized from Hologram format
  - Already JSON-decoded data in the format [version, data] where version is an integer
    and data is the serialized content in Hologram format

  This is the entry point for deserializing, which then recursively uses deserialize/2 for nested structures.
  """
  @spec deserialize(binary() | list()) :: any
  def deserialize(json_or_list)

  def deserialize(json) when is_binary(json) do
    json
    |> Jason.decode!()
    |> deserialize()
  end

  def deserialize([version, data]) do
    deserialize(version, data)
  end

  @doc """
  Deserializes a term serialized by the client and pre-decoded from JSON.
  """
  @spec deserialize(integer, map | String.t()) :: any
  def deserialize(version, data)

  def deserialize(3, %{"t" => "r", "n" => node, "c" => creation, "i" => id_words}) do
    node_len = byte_size(node)
    len = length(id_words)
    id_words_binary = for word <- id_words, into: <<>>, do: <<word::32>>

    # Build Erlang external term format for reference:
    # - 131: VERSION_NUMBER (ETF version)
    # - 90: NEWER_REFERENCE_EXT tag
    # - len::16: number of ID words (16-bit unsigned)
    # - 119: SMALL_ATOM_UTF8_EXT tag
    # - node_len::8: length of node name (8-bit unsigned)
    # - node::binary: node name as UTF-8 bytes
    # - creation::32: creation number (32-bit unsigned)
    # - id_words_binary::binary: ID words, each 32-bit big-endian
    binary =
      <<131, 90, len::16, 119, node_len::8, node::binary, creation::32, id_words_binary::binary>>

    :erlang.binary_to_term(binary, [:safe])
  end

  def deserialize(3, data) do
    deserialize(2, data)
  end

  def deserialize(2, "a" <> value) do
    String.to_existing_atom(value)
  end

  def deserialize(2, "b"), do: ""

  def deserialize(2, "b0" <> <<hex::binary>>) do
    Base.decode16!(hex, case: :lower)
  end

  def deserialize(2, "b" <> <<leftover_bits::binary-size(1), hex::binary>>) do
    bytes = Base.decode16!(hex, case: :lower)
    leftover_bit_count = String.to_integer(leftover_bits)

    <<full_bytes::binary-size(byte_size(bytes) - 1), left_aligned_leftover_byte::integer>> = bytes
    right_aligned_leftover_byte = Bitwise.bsr(left_aligned_leftover_byte, 8 - leftover_bit_count)
    <<full_bytes::binary, right_aligned_leftover_byte::size(leftover_bit_count)>>
  end

  def deserialize(2, "c" <> data) do
    [module_str, function_str, arity_str] = String.split(data, @delimiter)

    module = Module.safe_concat([module_str])
    function = String.to_existing_atom(function_str)
    arity = IntegerUtils.parse!(arity_str)

    Function.capture(module, function, arity)
  end

  def deserialize(2, "f" <> value) do
    value
    |> Float.parse()
    |> elem(0)
  end

  def deserialize(2, "i" <> value) do
    IntegerUtils.parse!(value)
  end

  def deserialize(2, %{"t" => "l", "d" => data}) do
    Enum.map(data, &deserialize(2, &1))
  end

  def deserialize(2, %{"t" => "m", "d" => data}) do
    data
    |> Enum.map(fn [key, value] -> {deserialize(2, key), deserialize(2, value)} end)
    |> Enum.into(%{})
  end

  def deserialize(2, "o" <> data) do
    [major, minor] = decode_identifier_segments(data)
    IEx.Helpers.port(major, minor)
  end

  def deserialize(2, "p" <> data) do
    [x, y, z] = decode_identifier_segments(data)
    IEx.Helpers.pid(x, y, z)
  end

  def deserialize(2, "r" <> data) do
    [w, x, y, z] = decode_identifier_segments(data)
    IEx.Helpers.ref(w, x, y, z)
  end

  def deserialize(2, %{"t" => "t", "d" => data}) do
    data
    |> Enum.map(&deserialize(2, &1))
    |> List.to_tuple()
  end

  def deserialize(1, %{
        "type" => "anonymous_function",
        "capturedModule" => module_str,
        "capturedFunction" => function_str,
        "arity" => arity
      }) do
    module = Module.safe_concat([module_str])
    function = String.to_existing_atom(function_str)

    Function.capture(module, function, arity)
  end

  def deserialize(1, "__atom__:" <> value) do
    String.to_existing_atom(value)
  end

  def deserialize(1, "__binary__:" <> value) do
    value
  end

  def deserialize(1, %{"type" => "bitstring", "bits" => bits}) do
    BitstringUtils.from_bit_list(bits)
  end

  def deserialize(1, "__float__:" <> value) do
    value
    |> Float.parse()
    |> elem(0)
  end

  def deserialize(1, "__integer__:" <> value) do
    IntegerUtils.parse!(value)
  end

  def deserialize(1, %{"type" => "list", "data" => data}) do
    Enum.map(data, &deserialize(1, &1))
  end

  def deserialize(1, %{"type" => "map", "data" => data}) do
    data
    |> Enum.map(fn [key, value] -> {deserialize(1, key), deserialize(1, value)} end)
    |> Enum.into(%{})
  end

  def deserialize(1, %{"type" => "pid", "segments" => [x, y, z]}) do
    IEx.Helpers.pid(x, y, z)
  end

  def deserialize(1, %{"type" => "port", "value" => value}) do
    IEx.Helpers.port(value)
  end

  def deserialize(1, %{"type" => "reference", "value" => value}) do
    IEx.Helpers.ref(value)
  end

  def deserialize(1, %{"type" => "tuple", "data" => data}) do
    data
    |> Enum.map(&deserialize(1, &1))
    |> List.to_tuple()
  end

  @doc """
  Returns the delimiter string used for separating fields in serialized data.
  """
  @spec delimiter() :: String.t()
  def delimiter, do: @delimiter

  defp decode_identifier_segments(data) do
    [_node, segments_str, _origin] = String.split(data, @delimiter)

    segments_str
    |> String.split(",")
    |> Enum.map(&IntegerUtils.parse!/1)
  end
end
