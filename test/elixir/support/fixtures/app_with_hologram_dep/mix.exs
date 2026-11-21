# credo:disable-for-this-file Credo.Check.Readability.Specs
# Stands for a project that depends on Hologram. The test gives it a lockfile path of its own.
defmodule Hologram.Test.Fixtures.AppWithHologramDep.MixProject do
  use Mix.Project

  def project do
    [
      app: :app_with_hologram_dep_fixture,
      version: "0.0.0"
    ]
  end
end
