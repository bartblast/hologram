# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.MixProject do
  use Mix.Project

  defp aliases do
    [
      eslint:
        "cmd assets/node_modules/.bin/eslint --color --config assets/.eslintrc.js --ext .mjs assets/js/** test/javascript/**",
      f: ["format", "prettier", "cmd cd test/features && mix format"],
      prettier:
        "cmd assets/node_modules/.bin/prettier '*.yml' '.github/**' 'assets/*.js' 'assets/*.json' 'assets/js/**' 'test/javascript/**' --config 'assets/.prettierrc.json'  --write",
      t: ["test", "test.js"],
      "test.js": [&test_js/1]
    ]
  end

  def application do
    if dep?() do
      [
        mod: {Hologram.Application, []},
        extra_applications: [:logger]
      ]
    else
      [
        extra_applications: [:logger]
      ]
    end
  end

  def dep? do
    __MODULE__.module_info()[:compile][:source]
    |> to_string()
    |> String.ends_with?("/deps/hologram/mix.exs")
  end

  defp deps do
    [
      {:beam_file, "~> 0.5"},
      {:benchee, "~> 1.0", only: :dev, runtime: false},
      {:benchee_markdown, "~> 0.3", only: :dev, runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ex_check, "~> 0.15", only: [:dev, :test], runtime: false},
      {:html_entities, "~> 0.5"},
      {:interceptor, "~> 0.5"},
      {:libgraph, "~> 0.16"},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test},
      {:phoenix, "~> 1.7"},
      {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:dev), do: ["benchmarks/support", "lib"]
  defp elixirc_paths(:test), do: ["lib", "test/elixir/fixtures", "test/elixir/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def package do
    [
      files: ["lib", "mix.exs", "README.md"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bartblast/hologram"},
      maintainers: ["Bart Blast"]
    ]
  end

  defp preferred_cli_env do
    [
      t: :test,
      "test.js": :test
    ]
  end

  def project do
    [
      aliases: aliases(),
      app: :hologram,
      deps: deps(),
      description:
        "Full stack isomorphic Elixir web framework that can be used on top of Phoenix.",
      dialyzer: [
        plt_add_apps: [:ex_unit, :iex, :mix],
        plt_core_path: Path.join(["priv", "plts", "core.plt"]),
        plt_local_path: Path.join(["priv", "plts", "project.plt"])
      ],
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      preferred_cli_env: preferred_cli_env(),
      start_permanent: Mix.env() == :prod,
      test_paths: ["test/elixir"],
      version: "0.1.0"
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
    {_result, status} = System.cmd("npm", cmd, opts)

    if status > 0 do
      Mix.raise("JavaScript tests failed!")
    end
  end
end
