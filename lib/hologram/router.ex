defmodule Hologram.Router do
  use Plug.Router

  alias Hologram.Controller
  alias Hologram.Router.PageModuleResolver
  alias Hologram.Runtime.Connection

  plug :match
  plug :dispatch

  post "/hologram/command" do
    Controller.handle_command_request(conn)
  end

  get "/hologram/page/:module_str" do
    page_module = Module.safe_concat([module_str])
    Controller.handle_subsequent_page_request(conn, page_module)
  end

  get "/hologram/websocket" do
    conn
    |> WebSockAdapter.upgrade(Connection, conn, timeout: 60_000)
    |> halt()
  end

  match _ do
    if page_module = PageModuleResolver.resolve(conn.request_path) do
      Controller.handle_initial_page_request(conn, page_module)
    else
      conn
    end
  end
end
