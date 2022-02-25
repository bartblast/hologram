defmodule Hologram.E2EWeb do
  def router do
    quote do
      use Phoenix.Router

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/hologram_e2e_web/templates",
        namespace: Hologram.E2EWeb

      import Phoenix.Controller, only: [view_module: 1, view_template: 1]

      unquote(view_helpers())
    end
  end

  defp view_helpers do
    quote do
      import Phoenix.View
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
