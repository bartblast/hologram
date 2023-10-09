defmodule Hologram.Router do
  @behaviour Plug

  alias Hologram.Router.PageModuleResover
  alias Hologram.Runtime.Controller
  alias Plug.Conn

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(%Conn{request_path: request_path} = conn, _opts) do
    if page_module = PageModuleResover.resolve(request_path) do
      Controller.handle_request(conn, page_module)
    else
      conn
    end
  end
end
