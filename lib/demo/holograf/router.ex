# TODO: test
defmodule Holograf.Router do
  defmacro __using__(_) do
    quote do
      require Holograf.Router
      import Holograf.Router
    end
  end

  defmacro holograf(path, view) do
    quote do
      get unquote(path), HolografController, :index, private: %{holograf_view: unquote(view)}
    end
  end
end
