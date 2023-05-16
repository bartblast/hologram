# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.MixProject do
  use Mix.Project

  defp aliases do
    [
      "format.all": ["format", "format.js"],
      "format.js":
        "cmd npx prettier 'assets/*.json' 'assets/js/*.mjs' 'test/javascript/**/*.mjs' --no-error-on-unmatched-pattern --write",
      "test.js": [&test_js/1]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:beam_file, "~> 0.5"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test]},
      {:interceptor, "~> 0.5"},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
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
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix]
      ],
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
