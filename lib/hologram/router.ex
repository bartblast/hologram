defmodule Hologram.Router do
  @behaviour Plug

  alias Hologram.Router.PageResolver
  alias Hologram.Runtime.Controller
  alias Hologram.Runtime.PageDigestLookup
  alias Plug.Conn

  @impl Plug
  def init(opts) do
    opts
    |> Keyword.put_new(:page_digest_lookup_store_key, PageDigestLookup)
    |> Keyword.put_new(:page_resolver_store_key, PageResolver)
  end

  @impl Plug
  def call(%Conn{request_path: request_path} = conn, opts) do
    if page_module = PageResolver.resolve(request_path, opts[:page_resolver_store_key]) do
      Controller.handle_request(conn, page_module, opts[:page_digest_lookup_store_key])
    else
      conn
    end
  end
end
