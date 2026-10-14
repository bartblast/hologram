defmodule HologramUmbrellaTests.MixProject do
  use Mix.Project

  defp aliases do
    [
      f: ["format"]
    ]
  end

  def project do
    [
      aliases: aliases(),
      apps_path: "apps",
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:ex_unit, :mix],
        plt_core_path: "priv/plts/core.plt",
        plt_local_path: "priv/plts/project.plt"
      ],
      elixir: "~> 1.0",
      # TODO: drop this entry once Bandit releases the fix for EEF-CVE-2026-105659 and the lock
      # is bumped past 1.12.5.
      #
      # The advisory is in Bandit's HTTP/2 flow control, and this app only serves plain HTTP/1
      # on localhost during a test run.
      hex: [ignore_advisories: ["EEF-CVE-2026-105659"]],
      # Mix reads :listeners from the project it runs as, which is the umbrella root -
      # declaring it in the endpoint app alone leaves Phoenix's code reloader unregistered.
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
