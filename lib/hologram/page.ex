defmodule Hologram.Page do
  defmacro __using__(_) do
    quote do
      import Hologram.Page
    end
  end

  def sigil_H(str, []), do: str

  def update(_state, _key, _value), do: nil
end
