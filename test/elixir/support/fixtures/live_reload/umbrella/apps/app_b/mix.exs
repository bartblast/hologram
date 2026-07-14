defmodule Hologram.Test.Fixtures.LiveReload.Umbrella.AppB.MixProject do
  use Mix.Project

  def project do
    [
      app: :app_b,
      elixirc_paths: ["lib", "support"],
      version: "0.0.0"
    ]
  end
end
