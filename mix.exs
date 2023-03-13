defmodule Hologram.MixProject do
  use Mix.Project

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end

  def package do
    [
      files: ["lib", "mix.exs", "README.md"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/bartblast/hologram"},
      maintainers: ["Bart Blast"]
    ]
  end

  def project do
    [
      app: :hologram,
      deps: deps(),
      description:
        "Full stack isomorphic Elixir web framework that can be used on top of Phoenix.",
      elixir: "~> 1.0",
      package: package(),
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end
end
