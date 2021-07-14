defmodule Hologram.Runtime.Reflection do
  # TODO: test
  defp find_pages do
    app_name = Mix.Project.get().project[:app]
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
