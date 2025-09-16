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

  @doc false
  @impl Mix.Task
  def run([project_name]) when is_binary(project_name) do
    create_project_dir(project_name)
    create_assets(project_name)

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
end
