defmodule App3.MixProject do
  use Mix.Project

  defp deps do
    [
      {:hologram,
       git: "https://github.com/bartblast/hologram.git",
       ref: "f02a87f7ff49e57bab19caa21dad9d2caae5951d"}
    ]
  end

  def project do
    [
      app: :app_3,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps: deps(),
      deps_path: "../../deps",
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: ["app"],
      lockfile: "../../mix.lock",
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end
end
