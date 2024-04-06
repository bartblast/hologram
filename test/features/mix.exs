defmodule HologramFeatureTests.MixProject do
  use Mix.Project

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end

  def application do
    [
      mod: {HologramFeatureTests.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:hologram, git: "https://github.com/bartblast/hologram.git"},
      {:jason, "~> 1.0"},
      {:phoenix, "~> 1.7"},
      {:plug_cowboy, "~> 2.0"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:wallaby, "~> 0.30", only: :test, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["app", "lib", "test/support"]
  defp elixirc_paths(_env), do: ["app", "lib"]

  def project do
    [
      aliases: aliases(),
      app: :hologram_feature_tests,
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      compilers: Mix.compilers() ++ [:hologram],
      deps: deps(),
      elixir: "~> 1.0",
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_add_deps: true,
        plt_core_path: "priv/plts/core.plt",
        plt_local_path: "priv/plts/project.plt"
      ],
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end
end
