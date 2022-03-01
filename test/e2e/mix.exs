defmodule HologramE2E.MixProject do
  use Mix.Project

  def project do
    [
      aliases: [],
      app: :hologram_e2e,
      compilers: Mix.compilers() ++ [:hologram],
      deps: deps(),
      elixir: "~> 1.12",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end

  def application do
    [
      mod: {HologramE2E.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:esbuild, "~> 0.4", runtime: Mix.env() == :dev},
      {:hologram, git: "https://github.com/bartblast/hologram.git"},
      {:jason, "~> 1.2"},
      {:phoenix, "~> 1.6"},
      {:plug_cowboy, "~> 2.5"},
      {:wallaby, "~> 0.29", only: :test, runtime: false}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/fixtures", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
