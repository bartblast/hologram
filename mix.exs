defmodule Hologram.MixProject do
  use Mix.Project

  def project do
    [
      aliases: aliases(),
      app: :hologram,
      compilers: Mix.compilers(),
      deps: deps(),
      description: "Full stack isomorphic Elixir web framework that can be used on top of Phoenix.",
      elixir: "~> 1.0",
      elixirc_paths: ["lib"],
      package: package(),
      preferred_cli_env: preferred_cli_env(),
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end

  defp aliases do
    [
      "format.all": [
        "format",
        "cmd npx prettier --write 'assets/**/*.js' 'test/js/**/*.js' '**/*.json'"
      ],
      "test.all": [&test_js/1, "test", "test.e2e"],
      "test.e2e": ["cmd cd test/e2e && mix test"],
      "test.js": [&test_js/1]
    ]
  end

  def application do
    [
      mod: {Hologram.Runtime.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:libgraph, "~> 0.13"}
    ]
  end

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
      "test.all": :test,
      "test.e2e": :test,
      "test.js": :test
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
