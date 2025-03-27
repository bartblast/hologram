# Docs: https://hexdocs.pm/ex_check/Mix.Tasks.Check.html#module-configuration-file

[
  tools: [
    # Lib
    {:check_test_file_names, "mix holo.test.check_file_names test/elixir/hologram"},
    {:compiler, env: %{"MIX_ENV" => "test"}},
    {:credo, env: %{"MIX_ENV" => "test"}},
    {:dialyzer, enabled: true},
    {:doctor, env: %{"MIX_ENV" => "test"}},
    {:eslint, "mix eslint"},
    {:ex_doc, env: %{"MIX_ENV" => "test"}},
    {:ex_unit, enabled: true},
    {:formatter, env: %{"MIX_ENV" => "test"}},
    {:hex_audit, "mix hex.audit"},
    {:mix_audit, env: %{"MIX_ENV" => "test"}},
    {:prettier,
     "assets/node_modules/.bin/prettier '*.yml' '.github/**' 'assets/*.json' 'assets/*.mjs' 'assets/js/**' 'benchmarks/javascript/**' 'test/javascript/**' --check --config 'assets/.prettierrc.json' --no-error-on-unmatched-pattern"},
    {:sobelow, "mix sobelow --config"},
    {:test_js, "mix test.js"},

    # Feature tests app
    {:features_check_test_file_names,
     command: "mix holo.test.check_file_names test", cd: "test/features"},
    {:features_compiler,
     command: "mix compile --all-warnings --warnings-as-errors", cd: "test/features"},
    {:features_credo, command: "mix credo --strict", cd: "test/features"},
    {:features_dialyzer, command: "mix dialyzer", cd: "test/features"},
    {:features_ex_unit, command: "mix test --warnings-as-errors", cd: "test/features"},
    {:features_formatter, command: "mix format --check-formatted", cd: "test/features"},
    {:features_hex_audit, command: "mix hex.audit", cd: "test/features"},
    {:features_mix_audit, command: "mix deps.unlock --check-unused", cd: "test/features"}
  ]
]
