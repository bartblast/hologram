defmodule Hologram.E2E.Web do
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
        root: "e2e/phoenix/web/templates",
        namespace: Hologram.E2E.Web

      import Phoenix.Controller, only: [view_module: 1, view_template: 1]

      unquote(view_helpers())
    end
  end

  defp view_helpers do
    quote do
      use Phoenix.HTML

      import Phoenix.View
      import Hologram.E2E.Web.ErrorHelpers

      alias Hologram.E2E.Web.Router.Helpers, as: Routes
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
