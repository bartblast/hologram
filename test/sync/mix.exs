defmodule HologramSyncTests.MixProject do
  use Mix.Project

  def application do
    [
      mod: {HologramSyncTests.Application, []},
      extra_applications: [:inets, :logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:hologram,
       git: "https://github.com/bartblast/hologram.git",
       ref: "de269455fd61c7ab33d3940faaa4be2a0f3fbf4e"},
      {:jason, "~> 1.0"},
      {:phoenix, "~> 1.7"}
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
      app: :hologram_sync_tests,
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      compilers: Mix.compilers() ++ [:hologram],
      deps: deps(),
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_core_path: "priv/plts/core.plt",
        plt_local_path: "priv/plts/project.plt"
      ],
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end
end
