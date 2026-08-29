defmodule HologramClusterTests.MixProject do
  use Mix.Project

  defp aliases do
    [
      f: ["format", "format.js"],
      "format.js":
        "cmd ../../assets/node_modules/.bin/prettier 'assets/js/**' --config '../../assets/.prettierrc.json' --write",
      "format.js.check":
        "cmd ../../assets/node_modules/.bin/prettier 'assets/js/**' --check --config '../../assets/.prettierrc.json' --no-error-on-unmatched-pattern"
    ]
  end

  def application do
    [
      mod: {HologramClusterTests.Application, []},
      extra_applications: [:iex, :logger, :runtime_tools]
    ]
  end

  defp deps do
    [
      {:credo, "~> 1.0", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:hologram,
       git: "https://github.com/bartblast/hologram.git",
       ref: "e68def6e3a84e5e23ca0cca70298a73ee5bfedb7"},
      {:jason, "~> 1.0"},
      {:mint, "~> 1.0", only: :test},
      {:phoenix, "~> 1.7"},
      {:plug_cowboy, "~> 2.0"},
      {:wallaby, "~> 0.30", only: :test}
    ]
  end

  defp elixirc_paths(:test) do
    ["app", "lib", "test/support"]
  end

  defp elixirc_paths(_env) do
    ["app", "lib"]
  end

  def project do
    [
      aliases: aliases(),
      app: :hologram_cluster_tests,
      # credo:disable-for-next-line Credo.Check.Refactor.AppendSingleItem
      compilers: Mix.compilers() ++ [:hologram],
      deps: deps(),
      elixir: "~> 1.0",
      elixirc_options: [warnings_as_errors: true],
      elixirc_paths: elixirc_paths(Mix.env()),
      dialyzer: [
        plt_add_apps: [:ex_unit, :iex, :mix],
        plt_core_path: "priv/plts/core.plt",
        plt_local_path: "priv/plts/project.plt"
      ],
      # TODO: drop these entries once a patched cowlib is registered - the audit itself
      # says when that has happened, printing that an entry no longer matches any
      # advisory and can be removed.
      #
      # cowlib reaches the build only through the Wallaby test-server stack
      # (plug_cowboy -> cowboy -> cowlib), and no cowlib version is registered as patched
      # for these three, so even 2.19.0 with its cow_http_struct_hd hardening is still
      # flagged. Response splitting is mitigated by cowboy's CR/LF header validation, and
      # nothing in the stack calls the affected cow_link:link/1.
      hex: [ignore_advisories: ["EEF-CVE-2026-43966", "EEF-CVE-2026-43969", "EEF-CVE-2026-43971"]],
      listeners: [Phoenix.CodeReloader],
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end
end
