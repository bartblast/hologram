# TODO: test
defmodule Holofograf.Router do
  defmacro __using__(_) do
    quote do
      require Holofograf.Router
      import Holofograf.Router
    end
  end

  defmacro holograf(path, view) do
    quote do
      get unquote(path), HolofografController, :index, private: %{holograf_view: unquote(view)}
    end
  end
end
