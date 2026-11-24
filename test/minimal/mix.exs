defmodule HologramMinimalTests.MixProject do
  use Mix.Project

  def application do
    [
      mod: {HologramMinimalTests.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:hologram,
       git: "https://github.com/bartblast/hologram.git",
       ref: "7f70ae092c02b4bdc5e38d093d0d2de714b5a759"},
      {:jason, "~> 1.0"},
      {:phoenix, "~> 1.7"}
    ]
  end

  def project do
    [
      app: :hologram_minimal_tests,
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      compilers: Mix.compilers() ++ [:hologram],
      deps: deps(),
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: ["app", "lib"],
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
