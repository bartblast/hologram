defmodule App3.MixProject do
  use Mix.Project

  defp deps do
    [
      {:hologram,
       git: "https://github.com/bartblast/hologram.git",
       ref: "86d57274b011ed8ef17e0e8785b0a806504e3dd7"}
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
