defmodule Hologram.Test.TLSProxy do
  @moduledoc false

  # Stands between a connection and the database the config named when the proxy started, and
  # speaks TLS to the client when it asks for it, so that a test can tell whether a connection
  # went through TLS against a server that offers none.
  #
  # A PostgreSQL client asks with an SSLRequest before its startup message. The proxy answers S,
  # runs the TLS handshake with a certificate of its own test CA and relays the decrypted stream
  # to the server, which sees a plain connection. A connection that opens with anything else is
  # relayed as is. A failed handshake closes the connection, the way a server refusing it would.
  #
  # The upstream is read once, at start, so that a test can then point the config at the proxy.

  use GenServer

  require Record

  alias Hologram.DB.Config

  Record.defrecordp(
    :attribute,
    :AttributeTypeAndValue,
    Record.extract(:AttributeTypeAndValue,
      from_lib: "public_key/include/public_key.hrl"
    )
  )

  Record.defrecordp(
    :extension,
    :Extension,
    Record.extract(:Extension, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :otp_certificate,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :otp_tbs_certificate,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate,
      from_lib: "public_key/include/public_key.hrl"
    )
  )

  @common_name_oid {2, 5, 4, 3}

  @handshake_timeout_ms :timer.seconds(5)

  @ssl_request <<8::32, 80_877_103::32>>

  @subject_alt_name_oid {2, 5, 29, 17}

  @doc """
  Returns the path of a PEM file holding the proxy's CA, which signed the certificate it presents.
  """
  @spec ca_cert_path(GenServer.server()) :: String.t()
  def ca_cert_path(proxy), do: GenServer.call(proxy, :ca_cert_path)

  @doc """
  Returns the paths of the PEM files of a client certificate and its key, signed by the CA the
  proxy trusts for client certificates, as `[cert_path: path, key_path: path]`.
  """
  @spec client_cert_paths(GenServer.server()) :: keyword(String.t())
  def client_cert_paths(proxy), do: GenServer.call(proxy, :client_cert_paths)

  @doc """
  Returns how many TLS sessions presented a client certificate the proxy accepted.
  """
  @spec client_cert_sessions(GenServer.server()) :: non_neg_integer
  def client_cert_sessions(proxy), do: GenServer.call(proxy, {:count, :client_cert_sessions})

  @doc """
  Returns how many connections the proxy relayed as is, without TLS.
  """
  @spec plain_sessions(GenServer.server()) :: non_neg_integer
  def plain_sessions(proxy), do: GenServer.call(proxy, {:count, :plain_sessions})

  @doc """
  Returns the port the proxy listens on.
  """
  @spec port(GenServer.server()) :: :inet.port_number()
  def port(proxy), do: GenServer.call(proxy, :port)

  @doc """
  Starts a proxy listening on a free port, relaying to the database the current config names.

  Options:

    * `:cert` - the certificate the proxy presents: `:localhost` (the default), issued for
      localhost in its subjectAltName; `:other_host`, issued for db.example.com in its
      subjectAltName; or `:common_name_only`, with no subjectAltName and db.example.com as its
      common name
    * `:client_cert` - whether the proxy asks the client for a certificate, false by default.
      A client that sends none still gets through
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @doc """
  Returns how many TLS handshakes the proxy completed.
  """
  @spec tls_sessions(GenServer.server()) :: non_neg_integer
  def tls_sessions(proxy), do: GenServer.call(proxy, {:count, :tls_sessions})

  @impl GenServer
  def init(opts) do
    # So that terminate/2 removes the PEM files when the test supervisor stops the proxy.
    Process.flag(:trap_exit, true)

    {:ok, _apps} = Application.ensure_all_started(:ssl)

    connection_opts = Config.connection_opts()
    upstream = {String.to_charlist(connection_opts[:hostname]), connection_opts[:port]}

    dir = Path.join(System.tmp_dir!(), "hologram_tls_proxy_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    certs = generate_certs(Keyword.get(opts, :cert, :localhost))

    ca_cert_path = write_pem!(dir, "ca.pem", [{:Certificate, certs.server_ca, :not_encrypted}])

    client_cert_paths = [
      cert_path:
        write_pem!(dir, "client.pem", [{:Certificate, certs.client_cert, :not_encrypted}]),
      key_path: write_pem!(dir, "client_key.pem", [pem_entry(certs.client_key)])
    ]

    client_cert_opts =
      if Keyword.get(opts, :client_cert, false) do
        [cacerts: [certs.client_ca], fail_if_no_peer_cert: false, verify: :verify_peer]
      else
        [verify: :verify_none]
      end

    ssl_opts = [cert: certs.server_cert, key: certs.server_key] ++ client_cert_opts

    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)
    proxy = self()

    spawn_link(fn -> accept_loop(listen_socket, proxy, upstream, ssl_opts) end)

    {:ok,
     %{
       ca_cert_path: ca_cert_path,
       client_cert_paths: client_cert_paths,
       client_cert_sessions: 0,
       dir: dir,
       plain_sessions: 0,
       port: port,
       tls_sessions: 0
     }}
  end

  @impl GenServer
  def handle_call(:ca_cert_path, _from, state), do: {:reply, state.ca_cert_path, state}

  def handle_call(:client_cert_paths, _from, state), do: {:reply, state.client_cert_paths, state}

  def handle_call({:count, key}, _from, state), do: {:reply, Map.fetch!(state, key), state}

  def handle_call(:port, _from, state), do: {:reply, state.port, state}

  @impl GenServer
  def handle_cast({:session, key}, state), do: {:noreply, Map.update!(state, key, &(&1 + 1))}

  # The accept loop ends normally once the listen socket closes, as the proxy stops. Any other
  # exit of it - a carrier linked to it crashing, say on an upstream that refused - stops the
  # proxy, so that a test reading a count after it fails at the call.
  @impl GenServer
  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}

  def handle_info({:EXIT, _pid, reason}, state), do: {:stop, reason, state}

  @impl GenServer
  def terminate(_reason, state) do
    File.rm_rf!(state.dir)
  end

  defp accept_loop(listen_socket, proxy, upstream, ssl_opts) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        carrier = spawn_link(fn -> await_client(proxy, upstream, ssl_opts) end)
        :ok = :gen_tcp.controlling_process(client, carrier)
        send(carrier, {:client, client})

        accept_loop(listen_socket, proxy, upstream, ssl_opts)

      {:error, :closed} ->
        :ok
    end
  end

  defp await_client(proxy, upstream, ssl_opts) do
    receive do
      {:client, client} -> carry(client, proxy, upstream, ssl_opts)
    end
  end

  defp carry(client, proxy, upstream, ssl_opts) do
    case :gen_tcp.recv(client, 8, @handshake_timeout_ms) do
      {:ok, @ssl_request} ->
        :ok = :gen_tcp.send(client, "S")
        carry_tls(client, proxy, upstream, ssl_opts)

      {:ok, first_bytes} ->
        GenServer.cast(proxy, {:session, :plain_sessions})
        upstream_socket = connect_upstream(upstream)
        :ok = :gen_tcp.send(upstream_socket, first_bytes)
        :ok = :inet.setopts(client, active: true)
        relay(:gen_tcp, client, upstream_socket)

      {:error, _reason} ->
        :gen_tcp.close(client)
    end
  end

  defp carry_tls(client, proxy, upstream, ssl_opts) do
    case :ssl.handshake(client, ssl_opts, @handshake_timeout_ms) do
      {:ok, tls_client} ->
        GenServer.cast(proxy, {:session, :tls_sessions})

        if match?({:ok, _cert}, :ssl.peercert(tls_client)) do
          GenServer.cast(proxy, {:session, :client_cert_sessions})
        end

        upstream_socket = connect_upstream(upstream)
        :ok = :ssl.setopts(tls_client, active: true)
        relay(:ssl, tls_client, upstream_socket)

      {:error, _reason} ->
        :gen_tcp.close(client)
    end
  end

  defp connect_upstream({host, port}) do
    {:ok, upstream_socket} = :gen_tcp.connect(host, port, [:binary, active: true])
    upstream_socket
  end

  # A certificate for db.example.com with the default subjectAltName left out, re-signed by the
  # CA - pkix_test_data/1 always gives a server certificate one.
  defp common_name_only(cert, ca_key) do
    otp_certificate(tbsCertificate: tbs) = :public_key.pkix_decode_cert(cert, :otp)

    extensions =
      tbs
      |> otp_tbs_certificate(:extensions)
      |> Enum.reject(&(extension(&1, :extnID) == @subject_alt_name_oid))

    subject =
      {:rdnSequence,
       [[attribute(type: @common_name_oid, value: {:printableString, ~c"db.example.com"})]]}

    tbs
    |> otp_tbs_certificate(extensions: extensions, subject: subject)
    |> :public_key.pkix_sign(ca_key)
  end

  # The key and digest are set, since the defaults can pick a curve or digest TLS 1.3 refuses.
  defp generate_certs(cert) do
    key_opts = [digest: :sha256, key: {:namedCurve, :secp256r1}]

    client_root = :public_key.pkix_test_root_cert(~c"Hologram test client CA", key_opts)
    server_root = :public_key.pkix_test_root_cert(~c"Hologram test server CA", key_opts)

    san_names =
      case cert do
        :localhost -> [dNSName: ~c"localhost"]
        _other_host -> [dNSName: ~c"db.example.com"]
      end

    san = extension(extnID: @subject_alt_name_oid, critical: false, extnValue: san_names)

    %{client_config: client_config, server_config: server_config} =
      :public_key.pkix_test_data(%{
        client_chain: %{intermediates: [], peer: key_opts, root: client_root},
        server_chain: %{
          intermediates: [],
          peer: [extensions: [san]] ++ key_opts,
          root: server_root
        }
      })

    server_cert =
      if cert == :common_name_only do
        common_name_only(server_config[:cert], server_root.key)
      else
        server_config[:cert]
      end

    %{
      client_ca: client_root.cert,
      client_cert: client_config[:cert],
      client_key: client_config[:key],
      server_ca: server_root.cert,
      server_cert: server_cert,
      server_key: server_config[:key]
    }
  end

  defp pem_entry({type, der}), do: {type, der, :not_encrypted}

  defp relay(transport, client, upstream_socket) do
    receive do
      {client_transport, ^client, data} when client_transport in [:ssl, :tcp] ->
        :gen_tcp.send(upstream_socket, data)
        relay(transport, client, upstream_socket)

      {:tcp, ^upstream_socket, data} ->
        transport.send(client, data)
        relay(transport, client, upstream_socket)

      {closed, _socket} when closed in [:ssl_closed, :tcp_closed] ->
        transport.close(client)
        :gen_tcp.close(upstream_socket)

      {error, _socket, _reason} when error in [:ssl_error, :tcp_error] ->
        transport.close(client)
        :gen_tcp.close(upstream_socket)
    end
  end

  defp write_pem!(dir, name, entries) do
    path = Path.join(dir, name)
    File.write!(path, :public_key.pem_encode(entries))
    path
  end
end
