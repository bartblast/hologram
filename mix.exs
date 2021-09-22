defmodule Hologram.MixProject do
  use Mix.Project

  def compilers do
    if is_dep?() do
      Mix.compilers()
    else
      compilers = [:phoenix, :gettext] ++ Mix.compilers()
      if Mix.env() == :test, do: compilers, else: compilers ++ [:hologram]
    end
  end

  def package do
    [
      files: ["lib/hologram", "mix.exs", "README.md"],
      maintainers: ["Segmetric", "Bart Blast"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/segmetric/hologram"}
    ]
  end

  defp preferred_cli_env do
    [
      "test.all": :test,
      "test.e2e": :test,
      "test.js": :test
    ]
  end

  def project do
    [
      aliases: aliases(),
      app: :hologram,
      compilers: compilers(),
      deps: deps(),
      description: "Work in progress...",
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      preferred_cli_env: preferred_cli_env(),
      start_permanent: Mix.env() == :prod,
      version: "0.0.1"
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    if is_dep?() do
      [
        extra_applications: [:logger]
      ]
    else
      [
        mod: {Hologram.E2E.Application, []},
        extra_applications: [:logger, :runtime_tools]
      ]
    end
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test) do
    if is_dep?() do
      ["lib"]
    else
      ["e2e", "lib", "test/fixtures", "test/support"]
    end
  end

  defp elixirc_paths(_) do
    if is_dep?() do
      ["lib"]
    else
      ["e2e", "lib"]
    end
  end

  defp is_dep? do
    __MODULE__.module_info()[:compile][:source]
    |> to_string()
    |> String.ends_with?("/deps/hologram/mix.exs")
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:esbuild, "~> 0.2", runtime: Mix.env() == :dev},
      {:file_system, "~> 0.2"},
      {:floki, ">= 0.30.0", only: :test},
      {:gettext, "~> 0.18"},
      {:jason, "~> 1.2"},
      {:phoenix, "~> 1.6.0-rc.0", override: true},
      {:phoenix_html, "~> 3.0"},
      {:phoenix_live_dashboard, "~> 0.5"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 0.16.0"},
      {:plug_cowboy, "~> 2.5"},
      {:saxy, "~> 1.4"},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:wallaby, "~> 0.29", only: :test, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      "assets.compile": &compile_assets/1,
      "assets.deploy": ["esbuild default --minify", "phx.digest"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      setup: ["deps.get", "ecto.setup"],
      test: ["test --exclude e2e"],
      "test.all": ["assets.compile", "cmd mix compile", &test_js/1, "test --include e2e"],
      "test.e2e": ["assets.compile", "cmd mix compile", "test --only e2e"],
      "test.js": ["assets.compile", &test_js/1]
    ]
  end

  defp compile_assets(_) do
    Mix.shell().cmd("cd assets && node_modules/webpack/bin/webpack.js --mode development")
  end

  defp test_js(args) do
    cmd =
      if Enum.empty?(args) do
        ["test"]
      else
        ["run", "test-file", "../#{hd(args)}"]
      end

    opts = [cd: "assets", into: IO.stream(:stdio, :line)]
    {_, status} = System.cmd("npm", cmd, opts)

    if status > 0 do
      Mix.raise "JavaScript tests failed!"
    end
  end
end
