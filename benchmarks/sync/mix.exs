defmodule HologramSyncBenchmark.MixProject do
  use Mix.Project

  def application do
    [
      mod: {HologramSyncBenchmark.Application, []},
      # :runtime_tools holds :scheduler, which the CPU figures are sampled with.
      extra_applications: [:inets, :logger, :runtime_tools]
    ]
  end

  # Hologram by path rather than by git ref, unlike the test apps: the benchmark measures
  # whatever the working tree holds, so a branch's figures can be taken before it is pushed.
  defp deps do
    [
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:hologram, path: "../.."},
      {:jason, "~> 1.0"},
      {:mint, "~> 1.0"},
      {:phoenix, "~> 1.7"}
    ]
  end

  def project do
    [
      app: :hologram_sync_benchmark,
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      compilers: Mix.compilers() ++ [:hologram],
      deps: deps(),
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: ["app", "lib"],
      dialyzer: [
        plt_add_apps: [:mix],
        plt_core_path: "priv/plts/core.plt",
        plt_local_path: "priv/plts/project.plt"
      ],
      start_permanent: false,
      version: "0.1.0"
    ]
  end
end
