# DEFER: test

defmodule Hologram.Router do
  alias Hologram.Runtime.StaticDigestStore
  alias Hologram.Template.Renderer
  alias Phoenix.Controller

  def init(opts) do
    opts
  end

  def call(%Plug.Conn{request_path: "/hologram/manifest.js"} = phx_conn, _opts) do
    body = StaticDigestStore.get_manifest()

    phx_conn
    |> Plug.Conn.put_resp_header("cache-control", "no-store")
    |> Plug.Conn.put_resp_header("content-type", "text/javascript")
    |> Plug.Conn.send_resp(200, body)
    |> Plug.Conn.halt()
  end

  # DEFER: test
  def static_path(file_path) do
    case StaticDigestStore.get(file_path) do
      {:ok, file_path} ->
        file_path

      :error ->
        file_path
    end
  end
end
