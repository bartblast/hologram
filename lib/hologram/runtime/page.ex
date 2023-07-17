defmodule Hologram.Page do
  defmacro __using__(_opts) do
    quote do
      import Hologram.Component, only: [sigil_H: 2]
      import Hologram.Page

      def __is_hologram_page__, do: true
    end
  end

  defmacro layout(module) do
    quote do
      def __hologram_layout__ do
        unquote(module)
      end
    end
  end

  defmacro route(path) do
    quote do
      def __hologram_route__ do
        unquote(path)
      end
    end
  end
end
