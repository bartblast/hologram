defmodule Hologram.Router do
  alias Hologram.Compiler.Reflection

  defmacro __using__(_) do
    quote do
      require Hologram.Router
      import Hologram.Router
    end
  end

  defp app_loaded? do
    app = Application.get_all_env(:hologram)[:otp_app]
    Application.ensure_loaded(app) == :ok
  end

  # TODO: test
  defmacro hologram_routes do
    if app_loaded?() do
      for page <- Reflection.list_compiled_pages() do
        quote do
          get unquote(page.route()), Hologram.Runtime.Controller, :index,
            private: %{hologram_page: unquote(page)}
        end
      end
    end
  end
end
