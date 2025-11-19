opts = [enabled: true, env: %{"MIX_ENV" => "test"}]

[
  retry: false,
  tools: [
    {:compiler, opts},
    {:credo, opts},
    {:dialyzer, opts},
    {:doctor, opts},
    {:eslint, "mix eslint", opts},
    {:ex_doc, enabled: false},
    {:ex_formatter, "mix format", opts},
    {:ex_test_file_names, "mix holo.test.check_file_names test/elixir/hologram", opts},
    {:ex_tests, "mix test", opts},
    # custom :ex_tests used instead of :ex_unit
    {:ex_unit, enabled: false},
    # custom :ex_formatter used instead of :formatter
    {:formatter, enabled: false},
    {:gettext, enabled: false},
    {:hex_audit, "mix hex.audit", opts},
    {:js_formatter,
     "assets/node_modules/.bin/prettier '*.yml' '.github/**' 'assets/*.json' 'assets/*.mjs' 'assets/js/**' 'benchmarks/javascript/**' 'test/javascript/**' --check --config 'assets/.prettierrc.json' --no-error-on-unmatched-pattern",
     opts},
    {:js_tests, "mix test.js", opts},
    {:mix_audit, opts},
    # custom :js_tests used instead of :npm_test
    {:npm_test, enabled: false},
    {:sobelow, "mix sobelow --config", opts},
    {:unused_deps, opts}
  ]
]
