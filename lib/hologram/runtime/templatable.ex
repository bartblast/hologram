defmodule Hologram.Runtime.Templatable do
  defmacro __using__(_opts) do
    quote do
      @callback template() :: (map -> list)
    end
  end
end
