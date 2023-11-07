[
  ## don't run tools concurrently
  # parallel: false,

  ## don't print info about skipped tools
  # skipped: false,

  ## always run tools in fix mode (put it in ~/.check.exs locally, not in project config)
  # fix: true,

  ## don't retry automatically even if last run resulted in failures
  # retry: false,

  ## list of tools (see `mix check` docs for a list of default curated tools)
  tools: [
    ## curated tools may be disabled (e.g. the check for compilation warnings)
    # {:compiler, false},

    ## ...or have command & args adjusted (e.g. enable skip comments for sobelow)
    # {:sobelow, "mix sobelow --exit --skip"},

    ## ...or reordered (e.g. to see output from dialyzer before others)
    # {:dialyzer, order: -1},

    ## ...or reconfigured (e.g. disable parallel execution of ex_unit in umbrella)
    # {:ex_unit, umbrella: [parallel: false]},

    ## custom new tools may be added (Mix tasks or arbitrary commands)
    # {:my_task, "mix my_task", env: %{"MIX_ENV" => "prod"}},
    # {:my_tool, ["my_tool", "arg with spaces"]}

    # Standard Checks
    {:credo, env: %{"MIX_ENV" => "test"}},
    {:compiler, env: %{"MIX_ENV" => "test"}},
    {:dialyzer, enabled: true},
    {:doctor, env: %{"MIX_ENV" => "test"}},
    {:ex_doc, env: %{"MIX_ENV" => "test"}},
    {:formatter, env: %{"MIX_ENV" => "test"}},
    {:mix_audit, env: %{"MIX_ENV" => "test"}},
    {:sobelow, "mix sobelow --config"},
    {:ex_unit, enabled: true},

    # custom checks  
    {:hex_audit, "mix hex.audit"},
    {:"formatter.js",
     "assets/node_modules/.bin/prettier 'assets/*.json' 'assets/js/*.mjs' 'assets/js/**/*.mjs' 'test/javascript/*.mjs' 'test/javascript/**/*.mjs' --check --config 'assets/.prettierrc.json' --no-error-on-unmatched-pattern"},
    {:check_file_names, "mix holo.test.check_file_names test/elixir/hologram"},
    {:eslint, "mix eslint"},
    {:"test.js", "mix test.js"},

    # Check feature tests in example App at test/features
    {:"features.compiler",
     command: "mix compile --all-warnings --warnings-as-errors", cd: "test/features"},
    {:"features.mix_audit", command: "mix deps.unlock --check-unused", cd: "test/features"},
    {:"features.hex_audit", command: "mix hex.audit", cd: "test/features"},
    {:"features.formatter", command: "mix format --check-formatted", cd: "test/features"},
    {:"features.credo", command: "mix credo --strict", cd: "test/features"},
    {:"features.dialyzer", command: "mix dialyzer", cd: "test/features"},
    {:"features.ex_unit", command: "mix test --warnings-as-errors", cd: "test/features"},
    {:"features.check_file_names",
     command:
       "mix holo.test.check_file_names test/hologram_feature_tests test/hologram_feature_tests_web",
     cd: "test/features"}
  ]
]
