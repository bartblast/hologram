defmodule Hologram.MixProject do
  use Mix.Project

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:doctor, "~> 0.21", only: [:dev, :test]},
      {:interceptor, "~> 0.5", only: [:dev, :test]}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/elixir/fixtures", "test/elixir/support"]
  defp elixirc_paths(_), do: ["lib"]

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
      elixirc_paths: elixirc_paths(Mix.env()),
      package: package(),
      start_permanent: Mix.env() == :prod,
      test_paths: ["test/elixir"],
      version: "0.1.0"
    ]
  end
end
