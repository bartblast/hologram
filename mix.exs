# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.MixProject do
  use Mix.Project

  @version "0.6.3"

  # Copied from Hologram.Commons.SystemUtils
  @windows_exec_suffixes [".bat", ".cmd", ".exe"]

  def aliases do
    [
      eslint:
        "cmd assets/node_modules/.bin/eslint --color --config assets/eslint.config.mjs assets/js/** benchmarks/javascript/** test/javascript/** --no-error-on-unmatched-pattern",
      f: ["format", "prettier", "cmd cd test/features && mix format"],
      prettier:
        "cmd assets/node_modules/.bin/prettier '*.yml' '.github/**' 'assets/*.json' 'assets/*.mjs' 'assets/js/**' 'benchmarks/javascript/**' 'test/javascript/**' --config 'assets/.prettierrc.json' --write",
      t: ["test", "test.js"],
      "test.js": [&test_js/1]
    ]
  end

  def application do
    if dep?() do
      [mod: {Hologram.Application, []}]
    else
      []
    end
  end

  def deps do
    [
      {:bandit, "~> 1.0"},
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
      {:jason, "~> 1.0"},
      {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
      {:mox, "~> 1.0", only: :test},
      {:phoenix, "~> 1.7"},
      {:phoenix_pubsub, "~> 2.0"},
      {:plug, "~> 1.0"},
      {:plug_crypto, "~> 2.0"},
      {:recode, "~> 0.7", only: :dev, runtime: false},
      {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false},
      {:tailwind, "~> 0.4", only: [:dev, :test], runtime: false},
      {:uuid, "~> 1.0"},
      {:websock_adapter, "~> 0.5"}
    ]
  end

  def elixirc_paths(:dev), do: ["benchmarks/elixir/support", "lib"]
  def elixirc_paths(:test), do: ["lib", "test/elixir/fixtures", "test/elixir/support"]
  def elixirc_paths(_env), do: ["lib"]

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
      links: %{
        "Website" => "https://hologram.page",
        "Forum" => "https://elixirforum.com/hologram",
        "Slack" => "https://elixir-lang.slack.com/channels/hologram",
        "Newsletter" => "https://hologram.page/newsletter",
        "Courses" => "https://hologram.page/courses",
        "GitHub" => "https://github.com/bartblast/hologram",
        "Sponsor" => "https://github.com/sponsors/bartblast"
      },
      maintainers: ["Bart Blast"]
    ]
  end

  def preferred_cli_env do
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
          Plug: [Hologram.Router, Hologram.Router.Helpers],
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

  # Copied from Hologram.Commons.SystemUtils
  # Executes the given command cross-platform.
  # Accepts either a bare command name (resolved via PATH) or an executable file path.
  # On Windows, .cmd/.bat wrappers must be executed via "cmd /c".
  # sobelow_skip ["CI.System"]
  # credo:disable-for-lines:11 Credo.Check.Design.DuplicatedCode
  defp cmd_cross_platform(command_name_or_path, args, opts) do
    windows? = match?({:win32, _name}, :os.type())

    resolved_command_path = resolve_command_path!(command_name_or_path, windows?)

    if windows? and String.match?(resolved_command_path, ~r/\.(cmd|bat)$/i) do
      System.cmd("cmd", ["/c", resolved_command_path | args], opts)
    else
      System.cmd(resolved_command_path, args, opts)
    end
  end

  defp dep? do
    __MODULE__.module_info()[:compile][:source]
    |> to_string()
    |> String.ends_with?("/deps/hologram/mix.exs")
  end

  # Copied from Hologram.Commons.SystemUtils
  defp find_windows_wrapper(explicit_command_path) do
    @windows_exec_suffixes
    |> Enum.map(&(explicit_command_path <> &1))
    |> Enum.find(&File.exists?/1)
  end

  # Copied from Hologram.Commons.SystemUtils
  defp has_windows_exec_ext?(path) do
    ext =
      path
      |> Path.extname()
      |> String.downcase()

    ext in @windows_exec_suffixes
  end

  # Copied from Hologram.Commons.SystemUtils
  defp resolve_command_path!(command_name_or_path, windows?) do
    has_separator? = String.contains?(command_name_or_path, ["/", "\\"])

    if has_separator? do
      resolve_explicit_command_path!(command_name_or_path, windows?)
    else
      case System.find_executable(command_name_or_path) do
        nil ->
          raise RuntimeError,
            message: "executable not found in PATH: #{command_name_or_path}"

        resolved_command_path ->
          resolved_command_path
      end
    end
  end

  # Copied from Hologram.Commons.SystemUtils
  defp resolve_explicit_command_path!(explicit_command_path, true) do
    if has_windows_exec_ext?(explicit_command_path) and File.exists?(explicit_command_path) do
      explicit_command_path
    else
      resolve_windows_executable_path!(explicit_command_path)
    end
  end

  # Copied from Hologram.Commons.SystemUtils
  defp resolve_explicit_command_path!(explicit_command_path, false) do
    if File.exists?(explicit_command_path) do
      explicit_command_path
    else
      raise RuntimeError, message: "executable not found at #{explicit_command_path}"
    end
  end

  # Copied from Hologram.Commons.SystemUtils
  defp resolve_windows_executable_path!(explicit_command_path) do
    if resolved_path = find_windows_wrapper(explicit_command_path) do
      resolved_path
    else
      if File.exists?(explicit_command_path) do
        explicit_command_path
      else
        raise RuntimeError, message: "executable not found at #{explicit_command_path}"
      end
    end
  end

  defp test_js(args) do
    cmd =
      if Enum.empty?(args) do
        ["test"]
      else
        ["run", "test-file", "../#{hd(args)}"]
      end

    opts = [cd: "assets", into: IO.stream(:stdio, :line)]

    cmd_cross_platform("npm", ["install"], opts)

    {_exit_msg, exit_status} = cmd_cross_platform("npm", cmd, opts)

    if exit_status > 0 do
      Mix.raise("JavaScript tests failed!")
    end
  end
end
