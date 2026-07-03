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
