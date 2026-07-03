defmodule App1.MixProject do
  use Mix.Project

  def application do
    [
      mod: {App1.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:app_2, in_umbrella: true},
      {:app_3, in_umbrella: true},
      {:hologram,
       git: "https://github.com/bartblast/hologram.git",
       ref: "2a78048b2005118dc2d887a9eb71994d6c899d7d"},
      {:jason, "~> 1.0"},
      {:phoenix, "~> 1.7"},
      {:plug_cowboy, "~> 2.0"}
    ]
  end

  def project do
    [
      app: :app_1,
      build_path: "../../_build",
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      compilers: Mix.compilers() ++ [:hologram],
      config_path: "../../config/config.exs",
      deps: deps(),
      deps_path: "../../deps",
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: ["app", "lib"],
      listeners: [Phoenix.CodeReloader],
      lockfile: "../../mix.lock",
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end
end
