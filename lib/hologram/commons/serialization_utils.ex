defmodule Hologram.Commons.SerializationUtils do
  # sobelow_skip ["Misc.BinToTerm"]
  def deserialize(data) do
    :erlang.binary_to_term(data, [:safe])
  end

  def serialize(data) do
    :erlang.term_to_binary(data, compressed: 9)
  end
end
