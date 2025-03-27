# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.MixProject do
  use Mix.Project

  @version "0.4.0"

  defp aliases do
    [
      eslint:
        "cmd assets/node_modules/.bin/eslint --color --config assets/eslint.config.mjs assets/js/** benchmarks/javascript/** test/javascript/**",
      f: ["format", "prettier", "cmd cd test/features && mix format"],
      prettier:
        "cmd assets/node_modules/.bin/prettier '*.yml' '.github/**' 'assets/*.json' 'assets/*.mjs' 'assets/js/**' 'benchmarks/javascript/**' 'test/javascript/**' --config 'assets/.prettierrc.json' --write",
      t: ["test", "test.js"],
      "test.js": [&test_js/1]
    ]
  end

  def application do
    if dep?() do
      [
        mod: {Hologram.Application, []},
        extra_applications: [:logger]
      ]
    else
      [
        extra_applications: [:logger]
      ]
    end
  end

  def dep? do
    __MODULE__.module_info()[:compile][:source]
    |> to_string()
    |> String.ends_with?("/deps/hologram/mix.exs")
  end

  defp deps do
    [
      {:beam_file, "0.6.2"},
      {:benchee, "~> 1.0", only: :dev, runtime: false},
      {:benchee_markdown, "~> 0.3", only: :dev, runtime: false},
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.21", only: [:dev, :test], runtime: false},
      {:ecto, "~> 3.0", only: :test, runtime: false},
      {:ex_check, "~> 0.15", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:file_system, "~> 1.0"},
      {:html_entities, "~> 0.5"},
      {:interceptor, "~> 0.5"},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test},
      {:phoenix, "~> 1.7"},
      {:recode, "~> 0.7", only: :dev, runtime: false},
      {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false}
    ]
  end

  defp elixirc_paths(:dev), do: ["benchmarks/support", "lib"]
  defp elixirc_paths(:test), do: ["lib", "test/elixir/fixtures", "test/elixir/support"]
  defp elixirc_paths(_env), do: ["lib"]

  def package do
    [
      files: [
        "assets/js",
        "assets/package.json",
        "config",
        "lib",
        ".formatter.exs",
        "LICENSE",
        "mix.exs",
        "README.md"
      ],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/bartblast/hologram"},
      maintainers: ["Bart Blast"]
    ]
  end

  defp preferred_cli_env do
    [
      t: :test,
      "test.js": :test
    ]
  end

  def project do
    [
      aliases: aliases(),
      app: :hologram,
      deps: deps(),
      description:
        "Full stack isomorphic Elixir web framework that can be used on top of Phoenix.",
      dialyzer: [
        plt_add_apps: [:ex_unit, :iex, :mix],
        plt_core_path: Path.join(["priv", "plts", "core.plt"]),
        plt_local_path: Path.join(["priv", "plts", "project.plt"])
      ],
      docs: [
        authors: ["Bart Blast"],
        groups_for_modules: [
          Main: [
            Hologram,
            Hologram.Component,
            Hologram.Component.Action,
            Hologram.Component.Command,
            Hologram.Page,
            Hologram.Server
          ],
          Plug: [Hologram.Router, Hologram.Router.Helpers, Hologram.Socket],
          UI: [Hologram.UI.Link, Hologram.UI.Runtime],
          Errors: [
            Hologram.AssetNotFoundError,
            Hologram.CompileError,
            Hologram.ParamError,
            Hologram.TemplateSyntaxError
          ]
        ],
        source_ref: "v#{@version}"
      ],
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      homepage_url: "https://hologram.page/",
      package: package(),
      preferred_cli_env: preferred_cli_env(),
      start_permanent: Mix.env() == :prod,
      source_url: "https://github.com/bartblast/hologram",
      test_paths: ["test/elixir"],
      version: @version,
      xref: [
        # These modules are used only in tests to test whether Hex.Solver's implementations
        # for Inspect and String.Chars protocols are excluded when building runtime and pages JavaScript files.
        exclude: [
          Inspect.Hex.Solver.PackageRange,
          String.Chars.Hex.Solver.PackageRange
        ]
      ]
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
    {_exit_msg, exit_status} = System.cmd("npm", cmd, opts)

    if exit_status > 0 do
      Mix.raise("JavaScript tests failed!")
    end
  end
end
