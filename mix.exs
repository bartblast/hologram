defmodule Hologram.MixProject do
  use Mix.Project

  defp aliases do
    [
      "format.all": [
        "format",
        "cmd npx prettier --write 'assets/**/*.js' 'test/js/**/*.js' '**/*.json'"
      ],
      test: ["test --exclude e2e"],
      "test.all": [&test_js/1, "test --include e2e"],
      "test.e2e": ["test --only e2e"],
      "test.js": [&test_js/1]
    ]
  end

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

  def compilers do
    case {is_dep?(), Mix.env()} do
      {true, _} ->
        Mix.compilers()

      {false, :test} ->
        Mix.compilers()

      {false, _} ->
        Mix.compilers() ++ [:hologram]
    end
  end

  defp deps do
    [
      {:ecto_sql, "~> 3.6"},
      {:esbuild, "~> 0.2", runtime: Mix.env() == :dev},
      {:file_system, "~> 0.2"},
      {:floki, ">= 0.30.0", only: :test},
      {:jason, "~> 1.2"},
      {:libgraph, "~> 0.13.3"},
      {:phoenix, "~> 1.6.2"},
      {:plug_cowboy, "~> 2.5"},
      {:saxy, "~> 1.4"},
      {:wallaby, "~> 0.29", only: :test, runtime: false}
    ]
  end

  defp elixirc_paths do
    case {is_dep?(), Mix.env()} do
      {true, _} ->
        ["lib"]

      {false, :test} ->
        ["e2e", "lib", "test/fixtures", "test/support"]

      {false, _} ->
        ["e2e", "lib"]
    end
  end

  def is_dep? do
    __MODULE__.module_info()[:compile][:source]
    |> to_string()
    |> String.ends_with?("/deps/hologram/mix.exs")
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
      elixirc_paths: elixirc_paths(),
      package: package(),
      preferred_cli_env: preferred_cli_env(),
      start_permanent: Mix.env() == :prod,
      version: "0.0.1"
    ]
  end

  defp test_js(args) do
    cmd =
      if Enum.empty?(args) do
        ["test"]
      else
        ["run", "test-file", "../#{hd(args)}"]
      end

    opts = [cd: "assets", into: IO.stream(:stdio, :line)]
    System.cmd("npm", ["install"], opts)
    {_, status} = System.cmd("npm", cmd, opts)

    if status > 0 do
      Mix.raise("JavaScript tests failed!")
    end
  end
end
