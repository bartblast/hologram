# TODO: test
defmodule Hologram.Router do
  defmacro __using__(_) do
    quote do
      require Hologram.Router
      import Hologram.Router
    end
  end

  defmacro hologram(path, view) do
    quote do
      get unquote(path), HologramController, :index, private: %{hologram_view: unquote(view)}
    end
  end
end
