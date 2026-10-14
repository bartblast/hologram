defmodule HologramClusterTests.MixProject do
  use Mix.Project

  defp aliases do
    [
      f: ["format", "format.js"],
      "format.js":
        "cmd ../../assets/node_modules/.bin/prettier 'assets/js/**' --config '../../assets/.prettierrc.json' --write",
      "format.js.check":
        "cmd ../../assets/node_modules/.bin/prettier 'assets/js/**' --check --config '../../assets/.prettierrc.json' --no-error-on-unmatched-pattern"
    ]
  end

  def application do
    [
      mod: {HologramClusterTests.Application, []},
      extra_applications: [:iex, :logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:hologram,
       git: "https://github.com/bartblast/hologram.git",
       ref: "aef90311792ec2d58215f0855820a299ad8f73c9"},
      {:jason, "~> 1.0"},
      {:mint, "~> 1.0", only: :test},
      {:phoenix, "~> 1.7"},
      {:wallaby, "~> 0.30", only: :test}
    ]
  end

  defp elixirc_paths(:test) do
    ["app", "lib", "test/support"]
  end

  defp elixirc_paths(_env) do
    ["app", "lib"]
  end

  def project do
    [
      aliases: aliases(),
      app: :hologram_cluster_tests,
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      compilers: Mix.compilers() ++ [:hologram],
      deps: deps(),
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [:ex_unit, :iex, :mix],
        plt_core_path: "priv/plts/core.plt",
        plt_local_path: "priv/plts/project.plt"
      ],
      # TODO: drop this entry once Bandit releases the fix for EEF-CVE-2026-105659 and the lock
      # is bumped past 1.12.5.
      #
      # The advisory is in Bandit's HTTP/2 flow control, and this app only serves plain HTTP/1
      # on localhost during a test run.
      hex: [ignore_advisories: ["EEF-CVE-2026-105659"]],
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end
end
