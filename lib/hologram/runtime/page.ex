defmodule Hologram.Page do
  defmacro __using__(_) do
    quote do
      import Hologram.Page
    end
  end

  def sigil_H(str, _), do: str

  def update(state, key, value) do
    Map.put(state, key, value)
  end
end
