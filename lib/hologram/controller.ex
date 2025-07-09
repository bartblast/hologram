defmodule Hologram.Controller do
  @moduledoc false

  alias Hologram.Server
  alias Hologram.Server.Cookie
  alias Hologram.Server.Metadata
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

      iex> cookie_struct = %Cookie{value: 123, path: "/"}
      iex> ops = %{"user_id" => {:put, 1752074624726958, cookie_struct}}
      iex> updated_conn = apply_cookie_ops(conn, ops)
      iex> updated_conn.resp_cookies["user_id"]
      # Returns the cookie data
  """
  @spec apply_cookie_ops(Plug.Conn.t(), %{String.t() => Metadata.cookie_op()}) :: Plug.Conn.t()
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
  Extracts param values from the given URL path corresponding to the route of the given page module.
  """
  @spec extract_params(String.t(), module) :: %{atom => any}
  def extract_params(url_path, page_module) do
    route_segments = String.split(page_module.__route__(), "/")
    url_path_segments = String.split(url_path, "/")

    route_segments
    |> Enum.zip(url_path_segments)
    |> Enum.reduce([], fn
      {":" <> key, value}, acc ->
        [{String.to_existing_atom(key), value} | acc]

      _non_param_segment, acc ->
        acc
    end)
    |> Enum.into(%{})
  end

  @doc """
  Handles the page request by building HTTP response.

  ## Parameters

    * `conn` - The Plug.Conn struct representing the HTTP request
    * `page_module` - The page module to render

  ## Returns

  The updated and halted Plug.Conn struct with the rendered HTML and applied cookies.
  """
  @spec handle_request(Plug.Conn.t(), module) :: Plug.Conn.t()
  # sobelow_skip ["XSS.HTML"]
  def handle_request(conn, page_module) do
    {conn_with_session, _session_id} = Session.init(conn)

    params = extract_params(conn_with_session.request_path, page_module)
    server_struct = Server.from(conn_with_session)
    opts = [initial_page?: true]

    {html, _component_registry, server_struct} =
      Renderer.render_page(page_module, params, server_struct, opts)

    conn_with_session
    |> apply_cookie_ops(server_struct.__meta__.cookie_ops)
    |> Controller.html(html)
    |> Plug.Conn.halt()
  end

  defp build_cookie_opts(cookie_struct) do
    [
      domain: cookie_struct.domain,
      http_only: cookie_struct.http_only,
      max_age: cookie_struct.max_age,
      path: cookie_struct.path,
      same_site: same_site_to_string(cookie_struct.same_site),
      secure: cookie_struct.secure
    ]
    |> Enum.filter(fn {_key, value} -> value != nil end)
  end

  defp same_site_to_string(:lax), do: "Lax"
  defp same_site_to_string(:none), do: "None"
  defp same_site_to_string(:strict), do: "Strict"
  defp same_site_to_string(nil), do: nil
end
