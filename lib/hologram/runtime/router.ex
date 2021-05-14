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

  defmacro hologram_routes do
    for page <- find_pages() do
      quote do
        get unquote(page.route()), HologramController, :index, private: %{hologram_page: unquote(page)}
      end
    end
  end

  defp find_pages do
    app_name = Mix.Project.get.project[:app]
    app_path = File.cwd!()

    pages_path =
      if path = Application.get_env(:hologram, :pages_path) do
        path
      else
        "#{app_path}/lib/#{app_name}_web/hologram/pages"
      end

    glob = "#{pages_path}/**/*.ex"
    regex = ~r/defmodule\s+([\w\.]+)\s+do\s+/

    Path.wildcard(glob)
    |> Enum.map(fn filepath ->
      code = File.read!(filepath)
      [_, module] = Regex.run(regex, code)
      String.to_existing_atom("Elixir.#{module}")
    end)
  end
end
