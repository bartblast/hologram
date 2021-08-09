defmodule Hologram.Runtime.Reflection do
  # TODO: refactor & test
  def app_name do
    Mix.Project.get().project[:app]
  end

  # TODO: refactor & test
  def app_path do
    File.cwd!()
  end

  # TODO: refactor & test
  def list_pages do
    glob = "#{pages_path()}/**/*.ex"
    regex = ~r/defmodule\s+([\w\.]+)\s+do\s+/

    Path.wildcard(glob)
    |> Enum.map(fn filepath ->
      code = File.read!(filepath)
      [_, module] = Regex.run(regex, code)
      String.to_atom("Elixir.#{module}")
    end)
  end

  # TODO: refactor & test
  def pages_path do
    case Application.get_env(:hologram, :pages_path) do
      nil ->
        "#{app_path()}/lib/#{app_name()}_web/hologram/pages"
      path ->
        path
    end
  end
end
