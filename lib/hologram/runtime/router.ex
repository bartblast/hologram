# DEFER: test

defmodule Hologram.Router do
  alias Hologram.Runtime.StaticDigestStore
  alias Hologram.Template.Renderer
  alias Phoenix.Controller

  def init(opts) do
    opts
  end

  def call(%Plug.Conn{request_path: "/hologram/manifest.js"} = conn, _opts) do
    body = StaticDigestStore.get_manifest()

    conn
    |> Conn.put_resp_header("cache-control", "no-store")
    |> Conn.put_resp_header("content-type", "text/javascript")
    |> Conn.send_resp(200, body)
    |> Conn.halt()
  end

  def call(%Plug.Conn{request_path: request_path} = phx_conn, _opts) do
    arg =
      get_path_segments(request_path)
      |> List.to_tuple()

    # apply/3 is used to prevent compile warnings about undefined module
    match_result = apply(Hologram.Runtime.RouterMatcher, :match, [arg])

    if match_result do
      {page, params} = match_result
      holo_conn = %Hologram.Conn{params: params}
      bindings = %{}
      output = Renderer.render(page, holo_conn, bindings)
      Controller.html(phx_conn, output)
    else
      phx_conn
    end
  end

  def get_path_segments(path) do
    path
    |> String.split("/")
    |> List.delete_at(0)
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
