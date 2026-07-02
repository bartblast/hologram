defmodule Hologram.Test.Fixtures.Umbrella.AppB.MixProject do
  use Mix.Project

  def project do
    [
      app: :app_b,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      elixirc_paths: ["lib", "support"],
      lockfile: "../../mix.lock",
      version: "0.0.0"
    ]
  end
end
