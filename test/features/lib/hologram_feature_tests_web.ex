defmodule HologramFeatureTestsWeb do
  def controller do
    quote do
      use Phoenix.Controller, formats: [:html, :json]
      import Plug.Conn
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
