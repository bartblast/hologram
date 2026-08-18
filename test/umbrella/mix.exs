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
