defmodule Hologram.Compiler.Reflection do
  # TODO: refactor & test
  def app_name do
    Mix.Project.get().project[:app]
  end

  # TODO: refactor & test
  def app_path do
    File.cwd!()
  end

  # TODO: refactor & test
  def list_pages(opts \\ []) do
    glob = "#{pages_path(opts)}/**/*.ex"
    regex = ~r/defmodule\s+([\w\.]+)\s+do\s+/

    Path.wildcard(glob)
    |> Enum.map(fn filepath ->
      code = File.read!(filepath)
      [_, module] = Regex.run(regex, code)
      String.to_atom("Elixir.#{module}")
    end)
  end

  # TODO: refactor & test
  def pages_path(opts \\ []) do
    config_pages_path = Application.get_env(:hologram, :pages_path)

    cond do
      opts[:pages_path] ->
        opts[:pages_path]

      config_pages_path ->
        config_pages_path

      true ->
        "#{app_path()}/lib/#{app_name()}_web/hologram/pages"
    end
  end

    @doc """
  Returns the file path of the given module's source code.

  ## Examples
      iex> Reflection.source_path(Hologram.Compiler.Helpers)
      "/Users/bart/Files/Projects/hologram/lib/hologram/compiler/helpers.ex"
  """
  @spec source_path(module()) :: String.t()

  def source_path(module) do
    module.module_info()[:compile][:source]
    |> to_string()
  end
end
