defmodule Hologram.MixProject do
  use Mix.Project

  def project do
    [
      aliases: aliases(),
      compilers: Mix.compilers(),
      preferred_cli_env: preferred_cli_env()
    ]
  end

  defp aliases do
    [
      "format.all": [
        "format",
        "cmd npx prettier --write 'assets/**/*.js' 'test/js/**/*.js' '**/*.json'"
      ],
      "test.all": [&test_js/1, "test", "test.e2e"],
      "test.e2e": ["cmd cd test/e2e && mix test"],
      "test.js": [&test_js/1]
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
      {:libgraph, "~> 0.13"},
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
      "test.e2e": :test,
      "test.js": :test
    ]
  end

  defp test_js(args) do
    cmd =
      if Enum.empty?(args) do
        ["test"]
      else
        ["run", "test-file", "../#{hd(args)}"]
      end

    opts = [cd: "assets", into: IO.stream(:stdio, :line)]
    System.cmd("npm", ["install"], opts)
    {_, status} = System.cmd("npm", cmd, opts)

    if status > 0 do
      Mix.raise("JavaScript tests failed!")
    end
  end
end
