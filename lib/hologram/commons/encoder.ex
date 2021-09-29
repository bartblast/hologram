defmodule Hologram.Commons.Encoder do
  def wrap_with_array(encoded_elems) do
    if encoded_elems != "", do: "[ #{encoded_elems} ]", else: "[]"
  end
end
