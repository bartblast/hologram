defmodule App3.MixProject do
  use Mix.Project

  defp deps do
    [
      {:hologram,
       git: "https://github.com/bartblast/hologram.git",
       ref: "4bfa53481ca12b725bf8ab9f7f361b850c4c5360"}
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
