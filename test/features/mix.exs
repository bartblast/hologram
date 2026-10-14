defmodule HologramFeatureTests.MixProject do
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
      mod: {HologramFeatureTests.Application, []},
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
       ref: "c989cb4b8a9c432bd36cad52606225f5a3c9a388"},
      {:jason, "~> 1.0"},
      {:mint, "~> 1.0", only: :test},
      {:phoenix, "~> 1.7"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
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
      app: :hologram_feature_tests,
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
      # The advisory is in Bandit's HTTP/2 flow control. This app serves HTTP/2 only over TLS
      # with HOLOGRAM_FEATURE_TESTS_HTTPS set, and either way only on 127.0.0.1 during a test run.
      hex: [ignore_advisories: ["EEF-CVE-2026-105659"]],
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end
end
