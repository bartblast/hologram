defmodule Hologram.Router do
  alias Hologram.Compiler.Reflection

  defmacro __using__(_) do
    quote do
      require Hologram.Router
      import Hologram.Router
    end
  end

  # TODO: test
  defmacro hologram_routes do
    for page <- Reflection.list_compiled_pages() do
      quote do
        get unquote(page.route()), Hologram.Runtime.Controller, :index,
          private: %{hologram_page: unquote(page)}
      end
    end
  end
end
