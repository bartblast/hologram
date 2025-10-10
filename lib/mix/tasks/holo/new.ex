defmodule Mix.Tasks.Holo.New do
  @moduledoc """
  Creates a new Hologram project.

  ## Usage

      $ mix holo.new my_project_name

  Creates a directory named `my_project_name` in the current directory
  with a basic Hologram project structure.
  """

  use Mix.Task

  @app_css_template ""

  @config_exs_template """
  # config.exs runs at compile-time. For loading env vars use runtime.exs instead.

  import Config

  config :my_app,
    ecto_repos: [MyApp.Repo],
    generators: [timestamp_type: :utc_datetime]

  config :my_app, Hologram.Endpoint,
    url: [host: "localhost"],
    adapter: Bandit.PhoenixAdapter

  import_config "\#{config_env()}.exs"
  """

  @dev_exs_template """
  # dev.exs runs at compile-time. For loading env vars use runtime.exs instead.

  import Config

  config :my_app, MyApp.Repo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "my_app_dev",
    stacktrace: true,
    show_sensitive_data_on_connection_error: true,
    pool_size: 10

  config :my_app, Hologram.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: String.to_integer(System.get_env("PORT") || "4000")],
    check_origin: false,
    code_reloader: true,
    debug_errors: true,
    secret_key_base: "$SECRET_KEY_BASE"
  """

  @mix_exs_template """
  defmodule MyApp.MixProject do
    use Mix.Project

    def project do
      [
        app: :my_app,
        compilers: Mix.compilers() ++ [:hologram],
        deps: deps(),
        elixirc_paths: ["app"],
        start_permanent: Mix.env() == :prod,
        version: "0.1.0"
      ]
    end

    defp deps do
      [
        {:hologram, "~> 0.6.3"}
      ]
    end
  end
  """

  @prod_exs_template """
  # prod.exs runs at compile-time. For loading env vars use runtime.exs instead.

  import Config
  """

  @runtime_exs_template """
  # runtime.exs runs at app startup. Use it for loading env vars.

  import Config

  Hologram.Config.init(:my_app, config_env())

  if System.get_env("HOLOGRAM_SERVER") do
    config :my_app, Hologram.Endpoint, server: true
  end

  if config_env() == :prod do
    pool_size = String.to_integer(System.get_env("POOL_SIZE") || "10")
    maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

    config :my_app, MyApp.Repo,
      url: System.fetch_env!("DATABASE_URL"),
      pool_size: pool_size,
      socket_options: maybe_ipv6

    host = System.get_env("HOLOGRAM_HOST") || "example.com"
    port = String.to_integer(System.get_env("PORT") || "4000")

    config :my_app, Hologram.Endpoint,
      url: [host: host, port: 443, scheme: "https"],
      # See the docs: https://hexdocs.pm/bandit/Bandit.html#t:options/0
      http: [
        ip: {0, 0, 0, 0, 0, 0, 0, 0},
        port: port
      ],
      secret_key_base: System.fetch_env!("SECRET_KEY_BASE")

    config :my_app, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
  end
  """

  @test_exs_template """
  # test.exs runs at compile-time. For loading env vars use runtime.exs instead.

  import Config

  config :my_app, MyApp.Repo,
    username: "postgres",
    password: "postgres",
    hostname: "localhost",
    database: "my_app_test_\#{System.get_env("MIX_TEST_PARTITION")}",
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: System.schedulers_online() * 2

  config :my_app, Hologram.Endpoint,
    http: [ip: {127, 0, 0, 1}, port: 4002],
    secret_key_base: "$SECRET_KEY_BASE",
    server: false
  """

  @doc false
  @impl Mix.Task
  def run([project_name]) when is_binary(project_name) do
    create_project_dir(project_name)
    create_assets(project_name)
    create_config(project_name)
    create_mix_exs(project_name)

    print_info("")
    print_info("Your Hologram project was created successfully.")

    :ok
  end

  def run([]) do
    print_error("Expected project name as argument")
    print_info("Usage: mix holo.new my_project_name")

    :error
  end

  def run(_args) do
    print_error("Expected exactly one argument (project name)")
    print_info("Usage: mix holo.new my_project_name")

    :error
  end

  defp create_assets(project_name) do
    print_info("* creating #{project_name}/assets/css/app.css")

    assets_css_dir = Path.join([project_name, "assets", "css"])
    File.mkdir_p!(assets_css_dir)

    app_css_path = Path.join(assets_css_dir, "app.css")
    File.write!(app_css_path, @app_css_template)
  end

  defp create_config(project_name) do
    config_dir = Path.join(project_name, "config")
    File.mkdir_p!(config_dir)

    create_config_exs(project_name, config_dir)
    create_config_dev_exs(project_name, config_dir)
    create_config_prod_exs(project_name, config_dir)
    create_config_test_exs(project_name, config_dir)
    create_config_runtime_exs(project_name, config_dir)
  end

  defp create_config_dev_exs(project_name, config_dir) do
    print_info("* creating #{project_name}/config/dev.exs")

    dev_exs_path = Path.join(config_dir, "dev.exs")

    dev_exs_content =
      replace_placeholders(@dev_exs_template, project_name, secret_key_base: true)

    File.write!(dev_exs_path, dev_exs_content)
  end

  defp create_config_exs(project_name, config_dir) do
    print_info("* creating #{project_name}/config/config.exs")

    config_exs_path = Path.join(config_dir, "config.exs")
    config_exs_content = replace_placeholders(@config_exs_template, project_name)
    File.write!(config_exs_path, config_exs_content)
  end

  defp create_config_prod_exs(project_name, config_dir) do
    print_info("* creating #{project_name}/config/prod.exs")

    prod_exs_path = Path.join(config_dir, "prod.exs")
    prod_exs_content = replace_placeholders(@prod_exs_template, project_name)
    File.write!(prod_exs_path, prod_exs_content)
  end

  defp create_config_runtime_exs(project_name, config_dir) do
    print_info("* creating #{project_name}/config/runtime.exs")

    runtime_exs_path = Path.join(config_dir, "runtime.exs")
    runtime_exs_content = replace_placeholders(@runtime_exs_template, project_name)
    File.write!(runtime_exs_path, runtime_exs_content)
  end

  defp create_config_test_exs(project_name, config_dir) do
    print_info("* creating #{project_name}/config/test.exs")

    test_exs_path = Path.join(config_dir, "test.exs")

    test_exs_content =
      replace_placeholders(@test_exs_template, project_name, secret_key_base: true)

    File.write!(test_exs_path, test_exs_content)
  end

  defp create_mix_exs(project_name) do
    print_info("* creating #{project_name}/mix.exs")

    mix_exs_path = Path.join(project_name, "mix.exs")
    mix_exs_content = replace_placeholders(@mix_exs_template, project_name)
    File.write!(mix_exs_path, mix_exs_content)
  end

  defp create_project_dir(project_name) do
    print_info("* creating #{project_name}/")

    if File.exists?(project_name) do
      print_error("Directory #{project_name} already exists")
      System.halt(1)
    end

    File.mkdir_p!(project_name)
  end

  defp print_error(error) do
    Mix.shell().error(error)
  end

  defp print_info(info) do
    Mix.shell().info(info)
  end

  defp random_string(length) do
    length
    |> :crypto.strong_rand_bytes()
    |> Base.encode64(padding: false)
    |> binary_part(0, length)
  end

  defp replace_placeholders(template, project_name, opts \\ []) do
    output =
      template
      |> String.replace("my_app", project_name)
      |> String.replace("MyApp", Macro.camelize(project_name))

    if opts[:secret_key_base] do
      String.replace(output, "$SECRET_KEY_BASE", random_string(64))
    else
      output
    end
  end
end
