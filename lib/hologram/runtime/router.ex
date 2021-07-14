defmodule Hologram.Router do
  defmacro __using__(_) do
    quote do
      require Hologram.Router
      import Hologram.Router
    end
  end

  # TODO: consider - remove (it's not used anymore)
  defmacro hologram(path, page) do
    quote do
      get unquote(path), HologramController, :index, private: %{hologram_page: unquote(page)}
    end
  end

  # TODO: test
  defmacro hologram_routes do
    for page <- find_pages() do
      quote do
        get unquote(page.route()), HologramController, :index,
          private: %{hologram_page: unquote(page)}
      end
    end
  end
end
