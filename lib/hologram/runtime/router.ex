# DEFER: test

defmodule Hologram.Router do
  alias Hologram.Template.Renderer
  alias Phoenix.Controller
  alias Plug.Conn

  def init(opts) do
    opts
  end

  def call(%Conn{request_path: request_path} = conn, _opts) do
    arg =
      get_path_segments(request_path)
      |> List.to_tuple()

    # apply/3 is used to prevent compile warnings about undefined module
    match_result = apply(Hologram.Runtime.RouterMatcher, :match, [arg])

    if match_result do
      {page, params} = match_result
      output = Renderer.render(page, params)
      Controller.html(conn, output)
    else
      conn
    end
  end

  def get_path_segments(path) do
    path
    |> String.split("/")
    |> List.delete_at(0)
  end
end
