defmodule Hologram.Commons.BitstringUtils do
  @doc """
  Given a bitstring returns its corresponding list of bits (starting with the most significant bit at index 0).

  ## Examples

      iex> to_bit_list(<<25>>)
      [1, 1, 0, 0, 1]
  """
  @spec to_bit_list(bitstring) :: list(integer)
  def to_bit_list(bitstring) do
    for <<bit::1*1 <- bitstring>>, do: bit
  end
end
