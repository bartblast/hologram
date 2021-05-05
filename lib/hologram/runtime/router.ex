defmodule Hologram.Router do
  defmacro __using__(_) do
    quote do
      require Hologram.Router
      import Hologram.Router
    end
  end

  defmacro hologram(path, page) do
    quote do
      get unquote(path), HologramController, :index, private: %{hologram_page: unquote(page)}
    end
  end
end
