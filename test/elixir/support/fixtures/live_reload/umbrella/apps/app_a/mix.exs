defmodule Hologram.Test.Fixtures.LiveReload.Umbrella.AppA.MixProject do
  use Mix.Project

  def project do
    [
      app: :app_a,
      elixirc_paths: ["lib"],
      version: "0.0.0"
    ]
  end
end
