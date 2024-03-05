defmodule Hologram.Runtime.Templatable do
  alias Hologram.Component
  alias Hologram.Server

  defmacro __using__(_opts) do
    quote do
      alias Hologram.Runtime.Templatable

      @doc """
      Initializes component and server structs (when run on the server).
      """
      @callback init(%{atom => any}, Component.t(), Server.t()) ::
                  {Component.t(), Server.t()} | Component.t() | Server.t()

      @doc """
      Returns a template in the form of an anonymous function that given variable bindings returns a DOM.
      """
      @callback template() :: (map -> list)
    end
  end
end
