defmodule Hologram.Commons.SerializationUtils do
  @moduledoc false

  @doc """
  Deserializes binary data to Elixir term.

  ## Examples

      iex> deserialize(<<131, 104, 3, 97, 1, 97, 2, 97, 3>>)
      {1, 2, 3}
  """
  @spec deserialize(binary, boolean) :: term
  # sobelow_skip ["Misc.BinToTerm"]
  def deserialize(binary, allow_non_existing_atoms? \\ false) do
    opts = if allow_non_existing_atoms?, do: [], else: [:safe]
    :erlang.binary_to_term(binary, opts)
  end

  @doc """
  Serializes Elixir term to binary data.

  ## Examples

      iex> serialize({1, 2, 3})
      <<131, 104, 3, 97, 1, 97, 2, 97, 3>>
  """
  @spec serialize(term) :: binary
  def serialize(term) do
    :erlang.term_to_binary(term)
  end
end
