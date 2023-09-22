defmodule Hologram.Router do
  @behaviour Plug

  alias Hologram.Router.PageResolver
  alias Hologram.Runtime.Controller
  alias Plug.Conn

  @impl Plug
  def init(opts) do
    if opts[:persistent_term_key] do
      opts
    else
      Keyword.put(opts, :persistent_term_key, PageResolver.default_persistent_term_key())
    end
  end

  @impl Plug
  def call(%Conn{request_path: request_path} = conn, opts) do
    if page_module = PageResolver.resolve(request_path, opts[:persistent_term_key]) do
      Controller.handle_request(conn, page_module)
    else
      conn
    end
  end
end
