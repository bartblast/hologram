defmodule Hologram.Test.Fixtures.Umbrella.AppA.MixProject do
  use Mix.Project

  # This app deliberately doesn't set :elixirc_paths,
  # so that Mix's ["lib"] default applies.
  def project do
    [
      app: :app_a,
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      version: "0.0.0"
    ]
  end
end
