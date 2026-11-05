defmodule Hologram.Router do
  @moduledoc false

  use Plug.Router

  alias Hologram.Controller
  alias Hologram.LiveReload
  alias Hologram.Realtime.SSE
  alias Hologram.Router.PageModuleResolver
  alias Hologram.Runtime.Connection
  alias Hologram.Runtime.PlugConnUtils
  alias Hologram.Runtime.Session

  plug :match
  plug :dispatch

  # When Hologram is disabled (see `Hologram.enabled?/0`) its supervision tree -
  # including the page module resolver and asset registries that the routes
  # below depend on - is not started. Pass the connection straight through to
  # the next plug instead of attempting to serve a Hologram route and crashing.
  @doc false
  @spec call(Plug.Conn.t(), Plug.opts()) :: Plug.Conn.t()
  def call(conn, opts) do
    if Hologram.enabled?() do
      super(conn, opts)
    else
      conn
    end
  end

  post "/hologram/command" do
    maybe_await_model()
    Controller.handle_command_request(conn)
  end

  get "/hologram/identity-tag" do
    Controller.handle_identity_tag_request(conn)
  end

  post "/hologram/mutation" do
    maybe_await_model()
    Controller.handle_mutation_request(conn)
  end

  post "/hologram/page/:module_str" do
    page_module = Module.safe_concat([module_str])
    maybe_await_model()
    Controller.handle_subsequent_page_request(conn, page_module)
  end

  get "/hologram/ping" do
    Controller.handle_ping_request(conn)
  end

  get "/hologram/sse" do
    conn = PlugConnUtils.init_conn(conn)

    case Session.get_session_id(conn) do
      nil ->
        conn
        |> send_resp(401, "Unauthorized")
        |> halt()

      _session_id ->
        conn
        |> SSE.stream()
        |> halt()
    end
  end

  post "/hologram/sse/handshake" do
    Controller.handle_sse_handshake_request(conn)
  end

  get "/hologram/websocket" do
    conn
    |> WebSockAdapter.upgrade(Connection, conn, timeout: 60_000)
    |> halt()
  end

  # A request for a path that is no page goes on to the app's own routes, which can read the data
  # model too.
  match _ do
    maybe_await_model()

    if page_module = PageModuleResolver.resolve(conn.request_path) do
      Controller.handle_initial_page_request(conn, page_module)
    else
      conn
    end
  end

  # In dev, a save holds the data model until its live reload pass has compiled it (see
  # Hologram.LiveReload.await_model/0). The requests that can read the model wait for that here,
  # before they open any transaction, rather than being refused by their first read of it.
  defp maybe_await_model do
    if Hologram.env() == :dev, do: LiveReload.await_model()

    :ok
  end
end
