defmodule HologramEcosystemTests.MixProject do
  use Mix.Project

  def application do
    [
      mod: {HologramEcosystemTests.Application, []},
      extra_applications: [:iex, :logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:ash_money, "~> 0.2"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.0"},
      {:ecto_sql, "~> 3.0"},
      {:ex_money_sql, "~> 2.0"},
      {:hologram,
       git: "https://github.com/bartblast/hologram.git",
       ref: "62a31f6dfa490531733b384cb50de98a9546d2c9"},
      {:jason, "~> 1.0"},
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
      app: :hologram_ecosystem_tests,
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
