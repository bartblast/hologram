defmodule Hologram.MixProject do
  use Mix.Project

  def project do
    [
      compilers: Mix.compilers()
    ]
  end

  defp aliases do
    [
      "test.all": [&test_js/1, "test", "test.e2e"],
      "test.e2e": ["cmd cd test/e2e && mix test"]
    ]
  end

  def application do
    if is_dep?() do
      [
        mod: {Hologram.Runtime.Application, []},
        extra_applications: [:logger]
      ]
    else
      []
    end
  end

  defp deps do
    [
      {:deep_merge, "~> 1.0"},
      {:file_system, "~> 0.2"},
      {:jason, "~> 1.0"},
      {:phoenix, "~> 1.6"}
    ]
  end

  def is_dep? do
    __MODULE__.module_info()[:compile][:source]
    |> to_string()
    |> String.ends_with?("/deps/hologram/mix.exs")
  end

  defp preferred_cli_env do
    [
      "test.all": :test,
      "test.e2e": :test
    ]
  end
end
