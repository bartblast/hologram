defmodule Hologram.Component do
  defmacro __using__(_) do
    quote do
      import Hologram.Component
      import Hologram.Router, only: [static_path: 1]
      import Hologram.Runtime.Commons, only: [sigil_H: 2, update: 3]

      alias Hologram.Runtime.JS
      alias Hologram.UI.Link

      def is_component?, do: true
    end
  end
end
