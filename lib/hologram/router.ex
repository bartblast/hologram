defmodule Hologram.Router do
  use Plug.Router

  alias Hologram.Controller
  alias Hologram.Router.PageModuleResolver
  alias Hologram.Runtime.Connection

  plug :match
  plug :dispatch

  get "/hologram/websocket" do
    conn
    |> WebSockAdapter.upgrade(Connection, conn, timeout: 60_000)
    |> halt()
  end

  match _ do
    if page_module = PageModuleResolver.resolve(conn.request_path) do
      Controller.handle_page_request(conn, page_module, true)
    else
      conn
    end
  end
end
