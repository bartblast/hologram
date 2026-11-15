defmodule Hologram.Test.TCPProxy do
  @moduledoc false

  # Stands between a connection and the configured database, so that a test can decide what the
  # link does: a port nothing listens on refuses connections, a proxy started on it later makes the
  # database reachable, close_all/1 drops every session it carries, and freeze/1 makes them go
  # silent - nothing is forwarded either way and nothing is closed, the way a link that stopped
  # carrying packets looks to both ends.

  use GenServer

  alias Hologram.DB.Config

  @doc """
  Returns a port nothing listens on, for a connection to be refused on until a proxy starts there.
  """
  @spec closed_port() :: :inet.port_number()
  def closed_port do
    {:ok, socket} = :gen_tcp.listen(0, [])
    {:ok, port} = :inet.port(socket)
    :ok = :gen_tcp.close(socket)

    port
  end

  @doc """
  Closes both ends of every connection the proxy carries, and returns :ok once they are closed.
  The proxy goes on accepting new ones.
  """
  @spec close_all(GenServer.server()) :: :ok
  def close_all(proxy), do: GenServer.call(proxy, :close_all)

  @doc """
  Stops forwarding anything on the connections the proxy carries, without closing them, and
  returns :ok.
  """
  @spec freeze(GenServer.server()) :: :ok
  def freeze(proxy), do: GenServer.call(proxy, :freeze)

  @doc """
  Starts a proxy listening on the given port and forwarding each connection to the configured
  database.
  """
  @spec start_link(:inet.port_number()) :: GenServer.on_start()
  def start_link(port), do: GenServer.start_link(__MODULE__, port)

  @impl GenServer
  def init(port) do
    {:ok, listen_socket} = :gen_tcp.listen(port, [:binary, active: false, reuseaddr: true])
    proxy = self()

    spawn_link(fn -> accept_loop(listen_socket, proxy) end)

    {:ok, %{carriers: [], listen_socket: listen_socket}}
  end

  @impl GenServer
  def handle_call(:close_all, _from, state) do
    for carrier <- state.carriers do
      ref = Process.monitor(carrier)
      send(carrier, :close)

      receive do
        {:DOWN, ^ref, :process, ^carrier, _reason} -> :ok
      end
    end

    {:reply, :ok, %{state | carriers: []}}
  end

  def handle_call(:freeze, _from, state) do
    Enum.each(state.carriers, &send(&1, :freeze))

    {:reply, :ok, state}
  end

  def handle_call(:new_carrier, _from, state) do
    carrier =
      spawn_link(fn ->
        receive do
          {:client, client} -> carry(client)
        end
      end)

    {:reply, carrier, %{state | carriers: [carrier | state.carriers]}}
  end

  defp accept_loop(listen_socket, proxy) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client} ->
        carrier = GenServer.call(proxy, :new_carrier)
        :ok = :gen_tcp.controlling_process(client, carrier)
        send(carrier, {:client, client})

        accept_loop(listen_socket, proxy)

      {:error, :closed} ->
        :ok
    end
  end

  defp carry(client) do
    opts = Config.connection_opts()
    host = String.to_charlist(opts[:hostname])

    {:ok, upstream} = :gen_tcp.connect(host, opts[:port], [:binary, active: true])

    :ok = :inet.setopts(client, active: true)

    forward(client, upstream, false)
  end

  defp forward(client, upstream, frozen?) do
    receive do
      {:tcp, ^client, data} ->
        unless frozen?, do: :gen_tcp.send(upstream, data)
        forward(client, upstream, frozen?)

      {:tcp, ^upstream, data} ->
        unless frozen?, do: :gen_tcp.send(client, data)
        forward(client, upstream, frozen?)

      :freeze ->
        forward(client, upstream, true)

      :close ->
        close(client, upstream)

      {:tcp_closed, _socket} ->
        close(client, upstream)

      {:tcp_error, _socket, _reason} ->
        close(client, upstream)
    end
  end

  defp close(client, upstream) do
    :gen_tcp.close(client)
    :gen_tcp.close(upstream)
  end
end
