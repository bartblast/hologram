defmodule Hologram.Commons.BitstringUtils do
  def to_bit_list(bitstring) do
    for <<bit::1*1 <- bitstring>>, do: bit
  end
end
