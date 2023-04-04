defmodule Hologram.Commons.SerializationUtils do
  @doc """
  Deserializes binary data to Elixir term.

  ## Examples

      iex> deserialize(<<131, 104, 3, 97, 1, 97, 2, 97, 3>>)
      {1, 2, 3}
  """
  @spec deserialize(binary) :: term
  # sobelow_skip ["Misc.BinToTerm"]
  def deserialize(binary) do
    :erlang.binary_to_term(binary, [:safe])
  end

  @doc """
  Serializes Elixir term to binary data.

  ## Examples

      iex> serialize({1, 2, 3})
      <<131, 104, 3, 97, 1, 97, 2, 97, 3>>
  """
  @spec serialize(term) :: binary
  def serialize(term) do
    :erlang.term_to_binary(term, compressed: 9)
  end
end
