defmodule Hologram.Controller do
  @moduledoc false

  alias Hologram.Page
  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CookieStore
  alias Hologram.Server
  alias Hologram.Session
  alias Hologram.Template.Renderer
  alias Phoenix.Controller

  @doc """
  Applies a map of cookie operations to the given Plug.Conn struct.

  Takes a map of cookie operations where each key is a cookie name (string) and each value
  is either a put operation `{:put, timestamp, cookie_struct}` or a delete operation 
  `{:delete, timestamp}`.

  For put operations, the cookie value is encoded and set with the provided options.
  For delete operations, the cookie is removed from the response.

  ## Parameters

    * `conn` - The Plug.Conn struct to modify
    * `cookie_ops` - A map of cookie operations to apply

  ## Returns

  The updated Plug.Conn struct with the cookie operations applied.

  ## Examples

      iex> ops = %{"user_id" => {:put, 1752074624726958, %Cookie{value: 123}}}
      iex> updated_conn = apply_cookie_ops(conn, ops)
      iex> updated_conn.resp_cookies["user_id"]
      # Returns the cookie data
  """
  @spec apply_cookie_ops(Plug.Conn.t(), %{String.t() => CookieStore.op()}) :: Plug.Conn.t()
  def apply_cookie_ops(conn, cookie_ops) do
    Enum.reduce(cookie_ops, conn, fn {cookie_name, operation}, acc_conn ->
      case operation do
        {:put, _timestamp, cookie_struct} ->
          opts = build_cookie_opts(cookie_struct)

          Plug.Conn.put_resp_cookie(
            acc_conn,
            cookie_name,
            Cookie.encode(cookie_struct.value),
            opts
          )

        {:delete, _timestamp} ->
          Plug.Conn.delete_resp_cookie(acc_conn, cookie_name)
      end
    end)
  end

  @doc """
  Extracts (uncast) params from the given URL path corresponding to the route of the given page module.
  """
  @spec extract_params(String.t(), module) :: %{String.t() => String.t()}
  def extract_params(url_path, page_module) do
    route_segments = String.split(page_module.__route__(), "/")
    url_path_segments = String.split(url_path, "/")

    route_segments
    |> Enum.zip(url_path_segments)
    |> Enum.reduce([], fn
      {":" <> key, value}, acc ->
        [{key, value} | acc]

      _non_param_segment, acc ->
        acc
    end)
    |> Enum.into(%{})
  end

  @doc """
  Handles the initial page request by building HTTP response.

  ## Parameters

    * `conn` - The Plug.Conn struct representing the HTTP request
    * `page_module` - The page module to render

  ## Returns

  The updated and halted Plug.Conn struct with the rendered HTML and applied cookies.
  """
  @spec handle_initial_page_request(Plug.Conn.t(), module) :: Plug.Conn.t()
  def handle_initial_page_request(conn, page_module) do
    params =
      conn.request_path
      |> extract_params(page_module)
      |> Page.cast_params(page_module)

    handle_page_request(conn, page_module, params, true)
  end

  @doc """
  Handles a subsequent page request by building HTTP response.
  Exracts page parameters from the query string.

  ## Parameters

    * `conn` - The Plug.Conn struct representing the HTTP request
    * `page_module` - The page module to render

  ## Returns

  The updated and halted Plug.Conn struct with the rendered HTML and applied cookies.
  """
  @spec handle_subsequent_page_request(Plug.Conn.t(), module) :: Plug.Conn.t()
  def handle_subsequent_page_request(conn, page_module) do
    params =
      conn
      |> Plug.Conn.fetch_query_params()
      |> Map.get(:query_params)
      |> Page.cast_params(page_module)

    handle_page_request(conn, page_module, params, false)
  end

  defp build_cookie_opts(cookie_struct) do
    opts =
      [
        domain: cookie_struct.domain,
        http_only: cookie_struct.http_only,
        max_age: cookie_struct.max_age,
        path: cookie_struct.path,
        same_site: same_site_to_string(cookie_struct.same_site),
        secure: cookie_struct.secure
      ]

    Enum.filter(opts, fn {_key, value} -> value != nil end)
  end

  # sobelow_skip ["XSS.HTML”]
  defp handle_page_request(conn, page_module, params, initial_page?) do
    {conn_with_session, _session_id} = Session.init(conn)

    server_struct = Server.from(conn_with_session)
    opts = [initial_page?: initial_page?]

    {html, _component_registry, updated_server_struct} =
      Renderer.render_page(page_module, params, server_struct, opts)

    conn_with_session
    |> apply_cookie_ops(updated_server_struct.__meta__.cookie_ops)
    |> Controller.html(html)
    |> Plug.Conn.halt()
  end

  defp same_site_to_string(:lax), do: "Lax"
  defp same_site_to_string(:none), do: "None"
  defp same_site_to_string(:strict), do: "Strict"
  defp same_site_to_string(nil), do: nil
end
