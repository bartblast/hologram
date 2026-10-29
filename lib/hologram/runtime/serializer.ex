defmodule Hologram.Runtime.Serializer do
  @moduledoc false

  # TODO: consider moving to Hologram.Transport (transport/adapter layer) when splitting up Hologram.Runtime

  alias Hologram.Compiler.Encoder
  alias Hologram.Reflection
  alias Hologram.Runtime.Deserializer

  @delimiter Deserializer.delimiter()

  @version 4

  @opening "[#{@version},"

  @doc """
  Serializes the given term into the JSON the client's deserializer reads: `[version,data]`, where
  data is the term in Hologram's serialization format.

  Returns `{:ok, json}`, or `{:error, message}` when the term holds something the format can't
  carry: a function that is not a named function capture, or an improper list.

  ## Examples

      iex> serialize(:abc)
      {:ok, ~s'[4,"aabc"]'}
  """
  @spec serialize(any) :: {:ok, String.t()} | {:error, String.t()}
  def serialize(term) do
    {:ok, serialize!(term)}
  rescue
    error in ArgumentError ->
      {:error, error.message}
  end

  @doc """
  Serializes the given term into the JSON the client's deserializer reads, raising `ArgumentError`
  when the term holds something the format can't carry: a function that is not a named function
  capture, or an improper list.

  A bitstring that is a valid string is written as the string itself, any other one as hex. The JSON is
  written directly as iodata rather than built as a tree of maps for an encoder to walk, so a
  collection costs no map and no sorting of its keys.

  ## Examples

      iex> serialize!(%{name: "Hologram"})
      ~s'[4,{"t":"m","d":[["aname","sHologram"]]}]'
  """
  @spec serialize!(any) :: String.t()
  def serialize!(term) do
    serialized_term = serialize_term(term)
    IO.iodata_to_binary([@opening, serialized_term, "]"])
  end

  # A capture of a module's function, &Mod.fun/arity, is external. A capture of a function of the
  # module it is written in, &fun/arity, is local, and named after that function. An anonymous
  # function is local too, and named "-" followed by the function it is defined in.
  defp named_function?(function_info) do
    case function_info[:type] do
      :external ->
        true

      :local ->
        function_name = Atom.to_string(function_info[:name])
        not String.starts_with?(function_name, "-")
    end
  end

  defp serialize_bitstring(bitstring) do
    leftover_bit_count = rem(bit_size(bitstring), 8)
    full_byte_count = div(bit_size(bitstring), 8)

    <<full_bytes::binary-size(^full_byte_count), leftover_bits::bitstring>> = bitstring

    # The client holds leftover bits at the high end of the last byte.
    padding_bit_count = rem(8 - leftover_bit_count, 8)
    bytes = <<full_bytes::binary, leftover_bits::bitstring, 0::size(padding_bit_count)>>

    hex = Base.encode16(bytes, case: :lower)

    serialize_string("b#{leftover_bit_count}#{hex}")
  end

  defp serialize_function(function) do
    function_info = Function.info(function)

    if named_function?(function_info) do
      module = function_info[:module]

      module_str =
        if Reflection.elixir_module?(module) do
          Reflection.module_name(module)
        else
          ":#{module}"
        end

      function_str = Atom.to_string(function_info[:name])
      arity_str = Integer.to_string(function_info[:arity])

      serialize_string("c#{module_str}#{@delimiter}#{function_str}#{@delimiter}#{arity_str}")
    else
      raise ArgumentError,
        message: "term contains a function that is not a named function capture"
    end
  end

  defp serialize_identifier(prefix, identifier, segments) do
    identifier_node = node(identifier)
    node_str = Atom.to_string(identifier_node)
    segments_str = Enum.join(segments, ",")

    serialize_string("#{prefix}#{node_str}#{@delimiter}#{segments_str}#{@delimiter}server")
  end

  defp serialize_list_items([]), do: []

  defp serialize_list_items([item]), do: [serialize_term(item)]

  defp serialize_list_items([item | rest]) when is_list(rest) do
    [serialize_term(item), "," | serialize_list_items(rest)]
  end

  defp serialize_list_items(_improper_list) do
    raise ArgumentError, message: "term contains an improper list"
  end

  defp serialize_map_entry({key, value}) do
    ["[", serialize_term(key), ",", serialize_term(value), "]"]
  end

  defp serialize_reference(reference) do
    {node_str, creation, id_words} =
      reference
      |> :erlang.term_to_binary()
      |> Encoder.parse_reference_binary()

    serialized_node = serialize_string("j#{node_str}")
    serialized_id_words = Enum.map_intersperse(id_words, ",", &Integer.to_string/1)

    [
      ~s'{"t":"r","n":',
      serialized_node,
      ~s',"c":',
      Integer.to_string(creation),
      ~s',"i":[',
      serialized_id_words,
      "]}"
    ]
  end

  defp serialize_string(string) do
    Jason.encode_to_iodata!(string)
  end

  defp serialize_term(term) when is_atom(term) do
    serialize_string("a" <> Atom.to_string(term))
  end

  defp serialize_term(term) when is_binary(term) do
    if String.valid?(term) do
      serialize_string("s" <> term)
    else
      serialize_bitstring(term)
    end
  end

  defp serialize_term(term) when is_bitstring(term) do
    serialize_bitstring(term)
  end

  defp serialize_term(term) when is_float(term) do
    ["\"f", Float.to_string(term), "\""]
  end

  defp serialize_term(term) when is_function(term) do
    serialize_function(term)
  end

  defp serialize_term(term) when is_integer(term) do
    ["\"i", Integer.to_string(term), "\""]
  end

  defp serialize_term(term) when is_list(term) do
    [~s'{"t":"l","d":[', serialize_list_items(term), "]}"]
  end

  defp serialize_term(term) when is_map(term) do
    serialized_entries =
      term
      |> Map.to_list()
      |> Enum.map_intersperse(",", &serialize_map_entry/1)

    [~s'{"t":"m","d":[', serialized_entries, "]}"]
  end

  defp serialize_term(term) when is_pid(term) do
    serialize_identifier("p", term, Encoder.pid_segments(term))
  end

  defp serialize_term(term) when is_port(term) do
    serialize_identifier("o", term, Encoder.port_segments(term))
  end

  defp serialize_term(term) when is_reference(term) do
    serialize_reference(term)
  end

  defp serialize_term(term) when is_tuple(term) do
    serialized_items =
      term
      |> Tuple.to_list()
      |> Enum.map_intersperse(",", &serialize_term/1)

    [~s'{"t":"t","d":[', serialized_items, "]}"]
  end
end
