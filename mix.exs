# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.MixProject do
  use Mix.Project

  defp aliases do
    [
      eslint:
        "cmd assets/node_modules/.bin/eslint --config assets/.eslintrc.js --ext .mjs assets/js/** test/javascript/**",
      f: ["format", "format.js", "cmd cd test/features && mix format"],
      "format.js":
        "cmd assets/node_modules/.bin/prettier 'assets/*.js' 'assets/*.json' 'assets/js/*.mjs' 'assets/js/**/*.mjs' 'test/javascript/*.mjs' 'test/javascript/**/*.mjs' --config 'assets/.prettierrc.json' --no-error-on-unmatched-pattern --write",
      t: ["test", "test.js"],
      "test.js": [&test_js/1]
    ]
  end

  def application do
    opts = [extra_applications: [:logger]]

    if dep?() do
      [mod: {Hologram.Runtime.Application, []}] ++ opts
    else
      opts
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
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:interceptor, "~> 0.5"},
      {:libgraph, "~> 0.16"},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test},
      {:phoenix, "~> 1.7"},
      {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false}
    ]
  end

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
        plt_core_path: "priv/plts/core.plt",
        plt_local_path: "priv/plts/project.plt"
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

  defp test_js([]), do: do_test_js(["test"])
  defp test_js(args), do: do_test_js(["run", "test-file", "../#{hd(args)}"])

  defp do_test_js(args) do
    with opts <- [cd: "assets", into: IO.stream(:stdio, :line)],
         System.cmd("npm", ~w"install --loglevel=warn --no-audit --no-fund --no-progress", opts),
         {_result, status} when status > 0 <- System.cmd("npm", ["--quiet" | args], opts) do
      Mix.raise("JavaScript tests failed!")
    end
  end
end
