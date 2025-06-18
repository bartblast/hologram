defmodule Hologram.Router do
  use Plug.Router

  alias Hologram.Connection
  alias Hologram.Controller
  alias Hologram.Router.PageModuleResolver

  plug :match
  plug :dispatch

  get "/hologram/websocket" do
    conn
    |> WebSockAdapter.upgrade(Connection, conn, timeout: 60_000)
    |> halt()
  end

  match _ do
    if page_module = PageModuleResolver.resolve(conn.request_path) do
      Controller.handle_request(conn, page_module)
    else
      conn
    end
  end
end
