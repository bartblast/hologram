defmodule Hologram.Layout do
  defmacro __using__(_) do
    quote do
      import Hologram.Layout
      import Hologram.Runtime.Commons, only: [sigil_H: 2, update: 3]
    end
  end
end
