defmodule Hologram.DB.Config do
  @moduledoc false

  require Logger

  alias Hologram.Reflection

  @default_pool_size 10

  @default_port 5432

  # How long a held connection may sit idle before it pings the server - Postgrex.SimpleConnection's
  # default, set explicitly so that the check in held_connection_opts/1 reads the value sent.
  @idle_interval_ms :timer.seconds(5)

  # How long a held connection waits between tries while the database refuses it. One log line per
  # connection per try, so not much shorter; below the idle interval, see held_connection_opts/1.
  @reconnect_backoff_ms :timer.seconds(2)

  @discrete_keys [:database, :host, :password, :pool_size, :port, :ssl, :user]

  @first_statement_timeout_ms :timer.seconds(150)

  @keepalive_statement """
  SELECT
    set_config('tcp_keepalives_idle', '30', false),
    set_config('tcp_keepalives_interval', '10', false),
    set_config('tcp_keepalives_count', '3', false),
    set_config('tcp_user_timeout', '60000', false)
  """

  @required_keys [:database, :host, :password, :user]

  @ssl_modes [:require, :verify_ca, :verify_full]

  @ssl_path_entries [:ca_cert_path, :cert_path, :key_path]

  @doc """
  Returns the Postgrex options of the configured database in the current environment,
  with the given overrides applied.

  For a connection opened outside the pool - one that has to stay the same connection
  across several statements, or reach a different database on the same server.
  """
  @spec connection_opts(keyword) :: keyword
  def connection_opts(overrides \\ []) do
    :hologram
    |> Application.get_env(:database, [])
    |> resolve!(Hologram.env())
    |> postgrex_opts()
    |> Keyword.merge(overrides)
  end

  @doc """
  Logs that the calling connection lost its session to the database, then ends it with
  `{:shutdown, :connection_lost}`.

  What a connection started with held_connection_opts/1 does when its session is lost - see there.
  """
  @spec end_lost_session!() :: no_return
  def end_lost_session! do
    name =
      case Process.info(self(), :registered_name) do
        {:registered_name, name} when is_atom(name) -> name
        _no_name -> self()
      end

    Logger.error(
      "#{inspect(name)} lost its connection to the database, ending so that whatever depends on it is restarted with it"
    )

    exit({:shutdown, :connection_lost})
  end

  @doc """
  Returns how long a held connection (see held_connection_opts/1) waits for the answer to its
  session's first statement before it is killed: 150 seconds.

  Postgrex puts no bound on the wait, so a link that went silent as the session opened would hold
  the connection - for good once the server's side acknowledged the statement, about 15 minutes on
  Linux otherwise.

  Long, because a session-mode PgBouncer lets a client log in without a server connection and
  assigns one at the first statement. With its pool full, that statement waits in a queue served
  in order of arrival, and a connection killed while it waits rejoins at the back - a bound shorter
  than the wait would keep it out for as long as others are queued. PgBouncer ends the wait itself
  after its query_wait_timeout, 120 seconds by default, by closing the session, which the
  connection logs as lost and ends on. This bound sits above that default, so the pooler's limit
  comes first. Behind a pooler set to queue for longer, the kill comes first, and logs nothing.
  """
  @spec first_statement_timeout_ms() :: pos_integer
  def first_statement_timeout_ms, do: @first_statement_timeout_ms

  @doc """
  Returns the Postgrex options of a connection held outside the pool for as long as its session
  lasts, with the given overrides applied (see connection_opts/1).

  For a Postgrex.SimpleConnection whose session is the point: a listener's channels are registered
  on it, and the run lock connection's locks are held by it. Such a connection keeps trying its
  FIRST connect, every 2 seconds, and ends once a session it had is lost - its handle_disconnect/1
  calls end_lost_session!/0.

  Trying again rather than failing is the difference between a database that is away for a moment
  and a node that is gone. A connect that fails ends the process otherwise, and while the database
  refuses connections every restart fails within milliseconds - a supervisor gives up on the fourth
  restart within 5 seconds, then the one above it, up to the application. The connection waits
  instead, the way the pool's connections do, and a call made to it meanwhile is answered between
  two tries. A try against a host that drops packets rather than refusing them blocks the process
  until the connect timeout, which can outlast a call's timeout.

  Ending rather than reconnecting, because what was tied to the session is gone with it. A
  listener's announcements sent while it was away are lost without whoever listens through it
  knowing, and a run lock connection's locks are freed by the server. Its supervisor restarts it
  and whatever depends on it, which start over from where they stand.

  `auto_reconnect: true` is what has SimpleConnection try again after a failed connect - it would
  reconnect a lost session too, but the process has ended by then. The backoff has to stay below
  the connection's `:idle_interval`: a call arriving between two tries arms the idle ping, which
  crashes on the missing socket if it fires before the next try. Raises ArgumentError when the
  given overrides break that.
  """
  @spec held_connection_opts(keyword) :: keyword
  def held_connection_opts(overrides \\ []) do
    opts =
      [
        auto_reconnect: true,
        idle_interval: @idle_interval_ms,
        reconnect_backoff: @reconnect_backoff_ms,
        sync_connect: false
      ]
      |> Keyword.merge(overrides)
      |> connection_opts()

    backoff = Keyword.fetch!(opts, :reconnect_backoff)
    idle_interval = Keyword.fetch!(opts, :idle_interval)

    if backoff >= idle_interval do
      raise ArgumentError,
            "the reconnect backoff of a held connection must be below its idle interval, got #{backoff} ms and #{idle_interval} ms"
    end

    opts
  end

  @doc """
  Returns the statement that sets the server keepalives and user timeout of the session it runs
  in - the same figures as the run lock connection's (see Hologram.Job.RunLock).

  A node that vanishes leaves its sessions open on the server until the operating system there
  notices. The keepalives bound that to about a minute when the server has nothing unacknowledged
  on the link, rather than about two hours, and the user timeout when it has, rather than about 15
  minutes. A server whose platform has no user timeout keeps it at 0, and logs that it is not
  supported on each connect.

  Run once the connection is up rather than sent as startup parameters, which PgBouncer refuses
  unless told to ignore them. They bound only a direct connection: behind a pooler or a proxy the
  server's peer is the pooler, and its own keepalives toward the node are what bound how long the
  session lives.
  """
  @spec keepalive_statement() :: String.t()
  def keepalive_statement, do: @keepalive_statement

  @doc """
  Returns the Postgrex connection options of the given resolved database options (see
  resolve!/2): :database, :hostname, :password, :port, :ssl and :username. Leaves :pool_size out,
  which only the pool takes.

  The one place the resolved options are turned into the driver's, so that every connection -
  the pool's and those opened outside it - reaches the server the same way.

  An :ssl list maps to Postgrex's :ssl list by its mode:

    * `:require` - encrypts without checking the server's certificate
    * `:verify_ca` - also checks that the certificate was signed by a trusted CA, but not the
      host name it was issued for
    * `:verify_full` - also checks the host name

  The checking modes trust the CA in :ca_cert_path, or the system's CAs without it - Postgrex
  adds no CAs to a list. Raises ArgumentError when the system's CAs fail to load. :cert_path and
  :key_path give the client certificate and its key. The server name goes out in the handshake
  under every mode.
  """
  @spec postgrex_opts(keyword) :: keyword
  def postgrex_opts(resolved) do
    [
      database: resolved[:database],
      hostname: resolved[:host],
      password: resolved[:password],
      port: resolved[:port],
      ssl: postgrex_ssl_opts(resolved[:ssl]),
      username: resolved[:user]
    ]
  end

  @doc """
  Resolves the database connection options for the given environment from the given
  config keyword list (the value of `config :hologram, :database`).

  Discrete keys (:database, :host, :password, :pool_size, :port, :ssl, :user) are
  overlaid on the environment defaults, and components present in :url win over both.
  In :dev and :test the defaults are localhost with postgres/postgres credentials and the
  "<otp_app>_<env>" database. Other environments have no identity defaults - a missing
  :database, :host, :password or :user raises ArgumentError - while :port, :pool_size and
  :ssl default to 5432, 10 and false everywhere.

  :ssl is false for a plain connection, true for the same as `[mode: :verify_full]`, or a
  keyword list with these entries:

    * `:mode` - `:require`, `:verify_ca` or `:verify_full` (the default), see postgrex_opts/1
    * `:ca_cert_path` - the file of the CA to trust instead of the system's, for the modes
      that check the certificate
    * `:cert_path` and `:key_path` - the files of a client certificate and its key, set
      together

  Any other value, entry or entry value raises ArgumentError naming it.

  The :url follows PostgreSQL's connection URI format, and its query takes libpq's TLS
  parameters, each replacing only its own :ssl entry, the way the url's host and port replace
  their keys:

    * `sslmode` - `disable` turns ssl off whatever the key says, `require`, `verify-ca` and
      `verify-full` set the mode. `allow` and `prefer` raise, Postgrex can't fall back between
      an encrypted and a plain connection
    * `sslrootcert` - sets :ca_cert_path, or with `system` trusts the system's CAs, which as
      in libpq needs `verify-full`
    * `sslcert` and `sslkey` - set :cert_path and :key_path
    * `channel_binding` - `disable` and `prefer` have no effect, `require` raises, Postgrex
      never binds the channel

  The resulting list is checked like the key: :cert_path and :key_path need each other, and
  :ca_cert_path (`sslrootcert` too, unlike in libpq, where it implies `verify-ca`) needs
  `:verify_ca` or `:verify_full`. A `sslrootcert`, `sslcert` or `sslkey` while ssl ends up off
  raises, since it would be ignored. Any other parameter raises ArgumentError naming it, `ssl`
  and `pool_size` included, and so does a repeated one or a malformed percent-encoding. No
  message holds the url, which carries the password.

  Returns a keyword list sorted by key with the :database, :host, :password, :pool_size,
  :port, :ssl and :user options, :ssl holding false or the list sorted by entry, with its
  mode.
  """
  @spec resolve!(keyword, atom) :: keyword
  def resolve!(config, env) do
    {url_components, url_ssl} =
      config
      |> Keyword.get(:url)
      |> url_components!()

    resolved =
      env
      |> defaults()
      |> Keyword.merge(Keyword.take(config, @discrete_keys))
      |> Keyword.merge(url_components)
      |> Keyword.put_new(:pool_size, @default_pool_size)
      |> Keyword.put_new(:port, @default_port)
      |> Keyword.put_new(:ssl, false)
      |> Keyword.update!(:ssl, &resolve_ssl!(&1, url_ssl))

    validate_required!(resolved, env)

    Enum.sort(resolved)
  end

  # The verify_fun of the :verify_ca mode, see postgrex_opts/1. Public, so that the pool's options
  # hold a remote capture, which outlives a reload of this module.
  #
  # The ssl application's own handling of every event but the host name check failure - the
  # clauses of the fun it wraps a one-argument verify_fun in (convert_verify_fun/0 in ssl_config),
  # plus the rename of an expired root its default verify_fun makes (validate/4 in
  # ssl_certificate), which has it look for a cross-signed root in its place. The default renames
  # only for the trust anchor, which the fun can't see, so it renames for any self-signed
  # certificate: a rename that finds no other root goes back to cert_expired.
  #
  # Any verify_fun skips what the default verify_fun checks on a certificate the path validation
  # accepted: that it's signed with an algorithm among the handshake's, and the stapled OCSP
  # status, which Postgrex doesn't ask for. It skips them for the chain's CAs, and accepting the
  # host name failure skips them for the server certificate too. The signatures themselves are
  # still verified, and the revocation checks still run.
  @doc false
  @spec verify_ca_event(term, term, term) ::
          {:fail, {:bad_cert, term}} | {:unknown, term} | {:valid, term}
  def verify_ca_event(_cert, {:bad_cert, :hostname_check_failed}, state), do: {:valid, state}

  def verify_ca_event(cert, {:bad_cert, :cert_expired} = reason, _state) do
    if :public_key.pkix_is_self_signed(cert) do
      {:fail, {:bad_cert, :root_cert_expired}}
    else
      {:fail, reason}
    end
  end

  def verify_ca_event(_cert, {:bad_cert, _reason} = reason, _state), do: {:fail, reason}

  def verify_ca_event(_cert, {:extension, _extension}, state), do: {:unknown, state}

  def verify_ca_event(_cert, :valid, state), do: {:valid, state}

  def verify_ca_event(_cert, :valid_peer, state), do: {:valid, state}

  @doc """
  Logs that the database refused the keepalive settings (see keepalive_statement/0) with the given
  error, and returns :ok.

  What a connection does whose settings are best effort: they bound only how long the server keeps
  the session of a node that vanished, which nothing needs for being correct.
  """
  @spec warn_keepalives_refused(Exception.t()) :: :ok
  def warn_keepalives_refused(error) do
    Logger.warning(
      "the database refused the session's keepalive settings, a session of a node that vanished may stay open on the server for hours: #{Exception.message(error)}"
    )
  end

  defp defaults(env) when env in [:dev, :test] do
    [
      database: "#{Reflection.otp_app()}_#{env}",
      host: "localhost",
      password: "postgres",
      user: "postgres"
    ]
  end

  defp defaults(_env), do: []

  defp merge_url_ssl!(ssl, []), do: ssl

  defp merge_url_ssl!(ssl, url_ssl) do
    case {ssl, Keyword.fetch(url_ssl, :mode)} do
      {_ssl, {:ok, :disable}} ->
        validate_no_ignored_url_ssl_params!(url_ssl, "sslmode=disable turns ssl off")
        false

      {false, :error} ->
        validate_no_ignored_url_ssl_params!(
          url_ssl,
          "ssl is off - set sslmode in the url, or ssl: in config :hologram, :database"
        )

        false

      {false, {:ok, _mode}} ->
        url_ssl

      {ssl, _mode} ->
        Keyword.merge(ssl, url_ssl)
    end
  end

  defp normalize_ssl!(false), do: false

  defp normalize_ssl!(true), do: [mode: :verify_full]

  defp normalize_ssl!(ssl) when is_list(ssl) do
    if not Keyword.keyword?(ssl) do
      raise_invalid_ssl!(ssl)
    end

    Enum.each(ssl, &validate_ssl_entry!/1)
    validate_no_repeated_ssl_entries!(ssl)

    Keyword.put_new(ssl, :mode, :verify_full)
  end

  defp normalize_ssl!(ssl), do: raise_invalid_ssl!(ssl)

  defp postgrex_ssl_opts(false), do: false

  defp postgrex_ssl_opts(ssl) do
    mode = Keyword.fetch!(ssl, :mode)

    client_cert_opts =
      Enum.flat_map([cert_path: :certfile, key_path: :keyfile], fn {entry, opt} ->
        case Keyword.fetch(ssl, entry) do
          {:ok, path} -> [{opt, path}]
          :error -> []
        end
      end)

    postgrex_ssl_verify_opts(mode, ssl) ++ client_cert_opts
  end

  defp postgrex_ssl_verify_opts(:require, _ssl), do: [verify: :verify_none]

  # The server name still goes out in the handshake - hosts like Neon route the connection by it -
  # so the ssl application still checks the host name, and verify_ca_event/3 accepts its failure.
  # Turning the check off with server_name_indication: :disable would drop the name, and a match
  # function that accepts any name isn't asked about a certificate without a subjectAltName.
  defp postgrex_ssl_verify_opts(:verify_ca, ssl) do
    [verify: :verify_peer, verify_fun: {&__MODULE__.verify_ca_event/3, nil}] ++ ca_opts(ssl)
  end

  defp postgrex_ssl_verify_opts(:verify_full, ssl), do: [verify: :verify_peer] ++ ca_opts(ssl)

  defp ca_opts(ssl) do
    case Keyword.fetch(ssl, :ca_cert_path) do
      {:ok, path} -> [cacertfile: path]
      :error -> [cacerts: system_cacerts!()]
    end
  end

  defp raise_invalid_ssl!(ssl) do
    raise ArgumentError,
          "invalid ssl in config :hologram, :database - expected false, true or a keyword list, got: #{inspect(ssl)}"
  end

  # The key's ssl with the url's TLS parameters over it, each replacing only its own entry - see
  # resolve!/2.
  defp resolve_ssl!(ssl, url_ssl) do
    merged =
      ssl
      |> normalize_ssl!()
      |> merge_url_ssl!(url_ssl)

    case merged do
      false ->
        false

      merged ->
        validate_client_cert!(merged, url_ssl)
        validate_ca_cert_mode!(merged, url_ssl)

        merged
        |> Enum.flat_map(fn
          # sslrootcert=system: the system's CAs, which a checking mode trusts without a CA file.
          {:ca_cert_path, :system} -> []
          entry -> [entry]
        end)
        |> Enum.sort()
    end
  end

  defp ssl_counterpart(entry, url_ssl, given_entry) do
    if Keyword.has_key?(url_ssl, given_entry) do
      url_ssl_param(entry)
    else
      inspect(entry)
    end
  end

  defp ssl_source(entry, url_ssl) do
    if Keyword.has_key?(url_ssl, entry) do
      "url parameter #{url_ssl_param(entry)}"
    else
      "ssl entry #{inspect(entry)}"
    end
  end

  defp system_cacerts! do
    :public_key.cacerts_get()
  catch
    :error, {:failed_load_cacerts, reason} ->
      raise ArgumentError,
            "ssl in config :hologram, :database checks the server's certificate against the system's CAs, which failed to load (#{inspect(reason)}) - set ssl entry :ca_cert_path to the CA to trust"
  end

  defp validate_ca_cert_mode!(ssl, url_ssl) do
    mode = Keyword.fetch!(ssl, :mode)
    url_mode? = Keyword.has_key?(url_ssl, :mode)

    mode_source =
      if url_mode?, do: "sslmode=#{url_sslmode(mode)}", else: "mode #{inspect(mode)}"

    case Keyword.fetch(ssl, :ca_cert_path) do
      # As in libpq: the system's CAs vouch for whatever host they issued a certificate to, so
      # trusting them takes the host name check.
      {:ok, :system} when mode != :verify_full ->
        needed_mode = if url_mode?, do: "sslmode=verify-full", else: "mode :verify_full"

        unchecked =
          if mode == :require, do: "the server's certificate", else: "the server's host name"

        raise ArgumentError,
              "url parameter sslrootcert=system in config :hologram, :database needs #{needed_mode} - #{mode_source} doesn't check #{unchecked}"

      {:ok, _path} when mode == :require ->
        ca_source =
          if Keyword.has_key?(url_ssl, :ca_cert_path),
            do: "url parameter sslrootcert",
            else: "ssl entry :ca_cert_path"

        needed_modes =
          if url_mode?,
            do: "sslmode=verify-ca or sslmode=verify-full",
            else: "mode :verify_ca or :verify_full"

        raise ArgumentError,
              "#{ca_source} in config :hologram, :database needs #{needed_modes} - #{mode_source} doesn't check the server's certificate"

      _no_conflict ->
        :ok
    end
  end

  defp validate_client_cert!(ssl, url_ssl) do
    case {Keyword.has_key?(ssl, :cert_path), Keyword.has_key?(ssl, :key_path)} do
      {true, false} ->
        raise ArgumentError,
              "#{ssl_source(:cert_path, url_ssl)} in config :hologram, :database needs #{ssl_counterpart(:key_path, url_ssl, :cert_path)}, the key of the client certificate"

      {false, true} ->
        raise ArgumentError,
              "#{ssl_source(:key_path, url_ssl)} in config :hologram, :database needs #{ssl_counterpart(:cert_path, url_ssl, :key_path)}, the client certificate of the key"

      _both_or_neither ->
        :ok
    end
  end

  defp validate_no_ignored_url_ssl_params!(url_ssl, reason) do
    case Enum.find(url_ssl, fn {entry, _value} -> entry in @ssl_path_entries end) do
      {entry, _path} ->
        raise ArgumentError,
              "url parameter #{url_ssl_param(entry)} in config :hologram, :database would be ignored - #{reason}"

      nil ->
        :ok
    end
  end

  defp validate_no_repeated_ssl_entries!(ssl) do
    repeated =
      ssl
      |> Keyword.keys()
      |> Enum.frequencies()
      |> Enum.find(fn {_key, count} -> count > 1 end)

    case repeated do
      {key, _n} ->
        raise ArgumentError,
              "ssl entry #{inspect(key)} in config :hologram, :database is given more than once"

      nil ->
        :ok
    end
  end

  defp validate_ssl_entry!({:mode, mode}) when mode in @ssl_modes, do: :ok

  defp validate_ssl_entry!({:mode, mode}) do
    raise ArgumentError,
          "invalid ssl entry :mode in config :hologram, :database - expected :require, :verify_ca or :verify_full, got: #{inspect(mode)}"
  end

  defp validate_ssl_entry!({entry, path}) when entry in @ssl_path_entries do
    if is_binary(path) and path != "" do
      :ok
    else
      raise ArgumentError,
            "invalid ssl entry #{inspect(entry)} in config :hologram, :database - expected a non-empty string, got: #{inspect(path)}"
    end
  end

  defp validate_ssl_entry!({entry, _value}) do
    raise ArgumentError,
          "unknown ssl entry #{inspect(entry)} in config :hologram, :database - supported: :ca_cert_path, :cert_path, :key_path, :mode"
  end

  defp url_components!(nil), do: {[], []}

  defp url_components!(url) do
    uri = URI.parse(url)

    {user, password} =
      case String.split(uri.userinfo || "", ":", parts: 2) do
        [user, password] -> {user, password}
        [user] -> {user, nil}
      end

    database = uri.path && String.trim_leading(uri.path, "/")

    components = [
      database: database,
      host: uri.host,
      password: password,
      port: uri.port,
      user: user
    ]

    {Enum.reject(components, fn {_key, value} -> value in [nil, ""] end), url_ssl!(uri.query)}
  end

  # The url's query, read the way libpq reads a connection URI's. The messages name the parameter
  # and never hold the url, which carries the password.
  defp url_ssl!(nil), do: []

  defp url_ssl!(query) do
    # URI.query_decoder/2 keeps a malformed escape as it is and decodes %00 to a zero byte, both of
    # which libpq refuses.
    for pair <- String.split(query, "&"), pair =~ ~r/%(?![0-9A-Fa-f]{2})|%00/ do
      [name | _value] = String.split(pair, "=", parts: 2)

      raise ArgumentError,
            "invalid url parameter #{inspect(name)} in config :hologram, :database - malformed percent-encoding"
    end

    params =
      query
      |> URI.query_decoder(:rfc3986)
      |> Enum.to_list()

    url_ssl = Enum.flat_map(params, &url_ssl_entry!/1)

    repeated =
      params
      |> Enum.frequencies_by(fn {name, _value} -> name end)
      |> Enum.find(fn {_name, count} -> count > 1 end)

    case repeated do
      {name, _count} ->
        raise ArgumentError,
              "url parameter #{name} in config :hologram, :database is given more than once"

      nil ->
        url_ssl
    end
  end

  defp url_ssl_entry!({"sslmode", "disable"}), do: [mode: :disable]

  defp url_ssl_entry!({"sslmode", "require"}), do: [mode: :require]

  defp url_ssl_entry!({"sslmode", "verify-ca"}), do: [mode: :verify_ca]

  defp url_ssl_entry!({"sslmode", "verify-full"}), do: [mode: :verify_full]

  defp url_ssl_entry!({"sslmode", mode}) when mode in ["allow", "prefer"] do
    raise ArgumentError,
          "url parameter sslmode=#{mode} in config :hologram, :database isn't supported - Postgrex can't fall back between an encrypted and a plain connection, use sslmode=require or sslmode=disable"
  end

  defp url_ssl_entry!({"sslmode", mode}) do
    raise ArgumentError,
          "invalid url parameter sslmode in config :hologram, :database - expected disable, require, verify-ca or verify-full, got: #{inspect(mode)}"
  end

  # Postgrex never binds the channel, which both values allow.
  defp url_ssl_entry!({"channel_binding", value}) when value in ["disable", "prefer"], do: []

  defp url_ssl_entry!({"channel_binding", "require"}) do
    raise ArgumentError,
          "url parameter channel_binding=require in config :hologram, :database isn't supported - Postgrex can't bind the channel, remove the parameter"
  end

  defp url_ssl_entry!({"channel_binding", value}) do
    raise ArgumentError,
          "invalid url parameter channel_binding in config :hologram, :database - expected disable or prefer, got: #{inspect(value)}"
  end

  defp url_ssl_entry!({"sslrootcert", "system"}), do: [ca_cert_path: :system]

  defp url_ssl_entry!({name, path}) when name in ["sslcert", "sslkey", "sslrootcert"] do
    if path == "" do
      raise ArgumentError,
            "invalid url parameter #{name} in config :hologram, :database - expected a file path, got an empty value"
    end

    [{url_ssl_entry(name), path}]
  end

  defp url_ssl_entry!({"ssl", _value}) do
    raise ArgumentError,
          "url parameter ssl in config :hologram, :database isn't supported - use sslmode=verify-full, or ssl: in config :hologram, :database"
  end

  defp url_ssl_entry!({"pool_size", _value}) do
    raise ArgumentError,
          "url parameter pool_size in config :hologram, :database isn't supported - set pool_size: next to url: in config :hologram, :database"
  end

  defp url_ssl_entry!({name, _value}) do
    raise ArgumentError,
          "unknown url parameter #{inspect(name)} in config :hologram, :database - supported: channel_binding, sslcert, sslkey, sslmode, sslrootcert"
  end

  defp url_ssl_entry("sslcert"), do: :cert_path

  defp url_ssl_entry("sslkey"), do: :key_path

  defp url_ssl_entry("sslrootcert"), do: :ca_cert_path

  defp url_ssl_param(:ca_cert_path), do: "sslrootcert"

  defp url_ssl_param(:cert_path), do: "sslcert"

  defp url_ssl_param(:key_path), do: "sslkey"

  defp url_ssl_param(:mode), do: "sslmode"

  defp url_sslmode(:require), do: "require"

  defp url_sslmode(:verify_ca), do: "verify-ca"

  defp url_sslmode(:verify_full), do: "verify-full"

  defp validate_required!(resolved, env) do
    missing = Enum.reject(@required_keys, &Keyword.has_key?(resolved, &1))

    if missing != [] do
      missing_keys = Enum.join(missing, ", ")

      raise ArgumentError,
            "missing database configuration for #{inspect(env)} - set config :hologram, :database with discrete keys or url:, missing: #{missing_keys}"
    end

    :ok
  end
end
