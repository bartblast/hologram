defmodule Hologram.Page do
  defmacro __using__(_) do
    quote do
      require Hologram.Page
      import Hologram.Page
    end
  end

  def sigil_H(str, _), do: str

  def update(state, key, value) do
    Map.put(state, key, value)
  end

  defmacro route(path) do
    quote do
      def route do
        unquote(path)
      end
    end
  end
end
