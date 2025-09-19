defmodule Mix.Tasks.Holo.New do
  @moduledoc """
  Creates a new Hologram project.

  ## Usage

      $ mix holo.new my_project_name

  Creates a directory named `my_project_name` in the current directory
  with a basic Hologram project structure.
  """

  use Mix.Task

  @app_css_template """
  @import "tailwindcss" source("../../app");
  """

  @config_exs_template """
  import Config

  config :my_app,
    ecto_repos: [MyApp.Repo],
    generators: [timestamp_type: :utc_datetime]

  config :my_app, Hologram.Endpoint,
    url: [host: "localhost"],
    adapter: Bandit.PhoenixAdapter

  config :tailwind,
    version: "4.1.7",
    my_app: [
      args: ~w(
        --input=assets/css/app.css
        --output=priv/static/assets/css/app.css
      ),
      cd: Path.expand("..", __DIR__)
    ]

  import_config "\#{config_env()}.exs"
  """

  @doc false
  @impl Mix.Task
  def run([project_name]) when is_binary(project_name) do
    create_project_dir(project_name)
    create_assets(project_name)
    create_config(project_name)

    print_info("")
    print_info("Your Hologram project was created successfully.")

    :ok
  end

  def run([]) do
    print_error("Expected project name as argument")
    print_info("Usage: mix holo.new my_project_name")

    :error
  end

  def run(_args) do
    print_error("Expected exactly one argument (project name)")
    print_info("Usage: mix holo.new my_project_name")

    :error
  end

  defp create_assets(project_name) do
    print_info("* creating #{project_name}/assets/css/app.css")

    assets_css_dir = Path.join([project_name, "assets", "css"])
    File.mkdir_p!(assets_css_dir)

    app_css_path = Path.join(assets_css_dir, "app.css")
    File.write!(app_css_path, @app_css_template)
  end

  defp create_config(project_name) do
    print_info("* creating #{project_name}/config/config.exs")

    config_dir = Path.join(project_name, "config")
    File.mkdir_p!(config_dir)

    config_exs_path = Path.join(config_dir, "config.exs")
    File.write!(config_exs_path, replace_placeholders(project_name, @config_exs_template))
  end

  defp create_project_dir(project_name) do
    print_info("* creating #{project_name}/")

    if File.exists?(project_name) do
      print_error("Directory #{project_name} already exists")
      System.halt(1)
    end

    File.mkdir_p!(project_name)
  end

  defp print_error(error) do
    Mix.shell().error(error)
  end

  defp print_info(info) do
    Mix.shell().info(info)
  end

  defp replace_placeholders(project_name, template) do
    template
    |> String.replace("my_app", project_name)
    |> String.replace("MyApp", Macro.camelize(project_name))
  end
end
