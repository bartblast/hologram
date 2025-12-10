defmodule Hologram.Runtime.Reference do
  @moduledoc false

  import Bitwise

  @doc """
  Generates a unique ID string from timestamp, counter, and random components.
  """
  def generate_id(counter) when is_integer(counter) do
    timestamp = System.system_time(:nanosecond)
    random = :rand.uniform(0xFFFFFFFF)

    unique_id = timestamp <<< 32 ||| counter <<< 16 ||| random

    Integer.to_string(unique_id)
  end

  @doc """
  Builds a reference from a client ID and unique ID.
  """
  def build(client_id, unique_id_string)
      when is_binary(client_id) and is_binary(unique_id_string) do
    unique_id = String.to_integer(unique_id_string)
    build(client_id, unique_id)
  end

  def build(client_id, unique_id) when is_binary(client_id) and is_integer(unique_id) do
    node_name = "client_#{client_id}@hologram"

    id_words = [
      unique_id &&& 0xFFFFFFFF,
      unique_id >>> 32 &&& 0xFFFFFFFF,
      unique_id >>> 64 &&& 0xFFFFFFFF
    ]

    build_from_node(node_name, id_words)
  end

  @doc """
  Compares two references by their serialized binary representation.
  This is the correct way to check if two references are "the same"
  across different server instances.
  """
  def equal?(ref1, ref2) when is_reference(ref1) and is_reference(ref2) do
    :erlang.term_to_binary(ref1) == :erlang.term_to_binary(ref2)
  end

  @doc """
  Encodes a reference back to client_id and unique_id.
  """
  def encode(ref) when is_reference(ref) do
    binary = :erlang.term_to_binary(ref)

    case parse_reference_binary(binary) do
      {:ok, node_name, [word0, word1, word2]} ->
        client_id = extract_client_id(node_name)
        unique_id = word2 <<< 64 ||| word1 <<< 32 ||| word0

        {client_id, Integer.to_string(unique_id)}

      {:error, _reason} ->
        raise ArgumentError, "Cannot encode reference that wasn't created by Hologram.Reference"
    end
  end

  @doc """
  Tests consistency across server instances.
  """
  def test_consistency(client_id, unique_id) do
    ref = build(client_id, unique_id)
    binary = :erlang.term_to_binary(ref)

    %{
      client_id: client_id,
      unique_id: unique_id,
      reference: ref,
      binary_hex: Base.encode16(binary),
      note: "Compare binary_hex across servers - it should be identical!"
    }
  end

  @doc """
  Verify that two references built with same params are equal.
  """
  def verify_equality(client_id, unique_id) do
    ref1 = build(client_id, unique_id)
    ref2 = build(client_id, unique_id)

    %{
      ref1_display: inspect(ref1),
      ref2_display: inspect(ref2),
      erlang_equal: ref1 == ref2,
      binary_equal: equal?(ref1, ref2),
      note: "Display may differ, but binary_equal should be true!"
    }
  end

  # Private functions

  defp build_from_node(node_name, id_words) do
    binary = build_binary(node_name, id_words)
    :erlang.binary_to_term(binary, [:safe])
  end

  defp build_binary(node_name, id_words) when is_binary(node_name) and is_list(id_words) do
    node_name_bytes = :erlang.term_to_binary(String.to_atom(node_name))

    {atom_tag, atom_len, atom_bytes} =
      case node_name_bytes do
        <<131, 119, len::8, bytes::binary-size(len)>> ->
          {119, len, bytes}

        <<131, 100, len::16, bytes::binary-size(len)>> ->
          {100, len, bytes}
      end

    id_words_padded =
      (id_words ++ [0, 0, 0])
      |> Enum.take(3)

    creation = 0

    if atom_tag == 119 do
      <<
        131,
        114,
        3::16,
        119,
        atom_len::8,
        atom_bytes::binary,
        creation::32,
        Enum.at(id_words_padded, 0)::32,
        Enum.at(id_words_padded, 1)::32,
        Enum.at(id_words_padded, 2)::32
      >>
    else
      <<
        131,
        114,
        3::16,
        100,
        atom_len::16,
        atom_bytes::binary,
        creation::32,
        Enum.at(id_words_padded, 0)::32,
        Enum.at(id_words_padded, 1)::32,
        Enum.at(id_words_padded, 2)::32
      >>
    end
  end

  defp parse_reference_binary(binary) do
    case binary do
      # NEWER_REFERENCE_EXT format (tag 90) - what the BEAM converts to
      <<131, 90, 3::16, 119, atom_len::8, atom_bytes::binary-size(atom_len), _creation::32,
        word0::32, word1::32, word2::32>> ->
        node_name = atom_bytes
        {:ok, node_name, [word0, word1, word2]}

      <<131, 90, 3::16, 100, atom_len::16, atom_bytes::binary-size(atom_len), _creation::32,
        word0::32, word1::32, word2::32>> ->
        node_name = atom_bytes
        {:ok, node_name, [word0, word1, word2]}

      # NEW_REFERENCE_EXT format (tag 114) - original format
      <<131, 114, 3::16, 119, atom_len::8, atom_bytes::binary-size(atom_len), _creation::32,
        word0::32, word1::32, word2::32>> ->
        node_name = atom_bytes
        {:ok, node_name, [word0, word1, word2]}

      <<131, 114, 3::16, 100, atom_len::16, atom_bytes::binary-size(atom_len), _creation::32,
        word0::32, word1::32, word2::32>> ->
        node_name = atom_bytes
        {:ok, node_name, [word0, word1, word2]}

      _ ->
        {:error, :invalid_format}
    end
  end

  defp extract_client_id(node_name_bytes) when is_binary(node_name_bytes) do
    node_name = node_name_bytes

    case Regex.run(~r/^client_(.+)@hologram$/, node_name) do
      [_, client_id] -> client_id
      _ -> raise ArgumentError, "Invalid node name format: #{node_name}"
    end
  end
end
