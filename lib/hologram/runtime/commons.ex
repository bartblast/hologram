defmodule Hologram.Runtime.Commons do
  def sigil_H(str, _), do: String.trim(str)

  def update(state, key, value) do
    Map.put(state, key, value)
  end
end
