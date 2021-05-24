defmodule Hologram.Page do
  defmacro __using__(_) do
    quote do
      require Hologram.Page
      import Hologram.Page
      import Hologram.Runtime.Commons, only: [sigil_H: 2]
    end
  end

  defmacro route(path) do
    quote do
      def route do
        unquote(path)
      end
    end
  end

  def update(state, key, value) do
    Map.put(state, key, value)
  end
end
