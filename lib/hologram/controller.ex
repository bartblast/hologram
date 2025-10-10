defmodule Hologram.Controller do
  @moduledoc false

  require Logger

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Page
  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Runtime.Deserializer
  alias Hologram.Runtime.PlugConnUtils
  alias Hologram.Runtime.Session
  alias Hologram.Server
  alias Hologram.Template.Renderer

  @typedoc """
  A connection with parsed JSON body_params containing Hologram command data.
  The body_params should contain %{"_json" => [version, data]} directly.
  """
  @type command_conn :: %Plug.Conn{body_params: map}

  @doc """
  Applies a map of cookie operations to the given Plug.Conn struct.

  Takes a map of cookie operations where each key is a cookie name (string) and each value
  is either a `Cookie` struct representing a put operation or a `:delete` atom
  representing a delete operation.

  For put operations, the cookie value is encoded and set with the provided options.
  For delete operations, the cookie is removed from the response.

  ## Parameters

    * `conn` - The Plug.Conn struct to modify
    * `cookie_ops` - A map of cookie operations to apply

  ## Returns

  The updated Plug.Conn struct with the cookie operations applied.

  ## Examples

      iex> ops = %{"user_id" => %Cookie{value: 123}}
      iex> updated_conn = apply_cookie_ops(conn, ops)
      iex> updated_conn.resp_cookies["user_id"]
      # Returns the cookie data
  """
  @spec apply_cookie_ops(Plug.Conn.t(), %{String.t() => Cookie.op()}) :: Plug.Conn.t()
  def apply_cookie_ops(conn, cookie_ops) do
    Enum.reduce(cookie_ops, conn, fn {cookie_name, operation}, acc_conn ->
      case operation do
        %Cookie{value: cookie_value} = cookie_struct ->
          opts = build_cookie_opts(cookie_struct)

          Plug.Conn.put_resp_cookie(
            acc_conn,
            cookie_name,
            Cookie.encode(cookie_value),
            opts
          )

        :delete ->
          Plug.Conn.delete_resp_cookie(acc_conn, cookie_name)
      end
    end)
  end

  @doc """
  Applies session operations to the given Plug.Conn struct.
  """
  @spec apply_session_ops(Plug.Conn.t(), %{String.t() => Session.op()}) :: Plug.Conn.t()
  def apply_session_ops(conn, session_ops) do
    Enum.reduce(session_ops, conn, fn {key, operation}, acc_conn ->
      case operation do
        {:put, value} ->
          Plug.Conn.put_session(acc_conn, key, value)

        :delete ->
          Plug.Conn.delete_session(acc_conn, key)
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
  Handles HTTP POST command requests by building JSON response.

  ## Parameters

    * `conn` - The Plug.Conn struct representing the HTTP request with parsed JSON body_params

  ## Returns

  The updated and halted Plug.Conn struct with the JSON response and applied cookies.
  """
  @spec handle_command_request(command_conn()) :: Plug.Conn.t()
  def handle_command_request(initial_conn) do
    conn = PlugConnUtils.init_conn(initial_conn)

    if validate_csrf_token(conn) do
      payload =
        conn.body_params
        |> Map.get("_json")
        |> Deserializer.deserialize()

      %{module: module, name: name, params: params, target: target} = payload

      # TODO: uncomment when standalone Hologram is supported
      # {conn_with_session, _session_id} = Session.init(conn)
      server_struct = Server.from(conn)

      command_result = module.command(name, params, server_struct)

      {updated_server_struct, next_action} =
        process_command_result(command_result, server_struct, target)

      {encode_status, encoded_next_action} = Encoder.encode_term(next_action)
      command_status = if encode_status == :ok, do: 1, else: 0

      conn
      |> apply_session_ops(updated_server_struct.__meta__.session_ops)
      |> apply_cookie_ops(updated_server_struct.__meta__.cookie_ops)
      |> put_json_response(200, [command_status, encoded_next_action])
      |> Plug.Conn.halt()
    else
      Logger.warning("CSRF token validation failed")

      conn
      |> put_text_response(403, "Forbidden")
      |> Plug.Conn.halt()
    end
  end

  @doc """
  Handles the initial page HTTP GET request by building HTTP response.

  ## Parameters

    * `conn` - The Plug.Conn struct representing the HTTP request
    * `page_module` - The page module to render

  ## Returns

  The updated and halted Plug.Conn struct with the rendered HTML and applied cookies.
  """
  @spec handle_initial_page_request(Plug.Conn.t(), module) :: Plug.Conn.t()
  def handle_initial_page_request(initial_conn, page_module) do
    conn = PlugConnUtils.init_conn(initial_conn)

    params =
      conn.request_path
      |> extract_params(page_module)
      |> Page.cast_params(page_module)

    {conn_with_csrf_token, {masked_csrf_token, _unmasked_csrf_token}} =
      CSRFProtection.ensure_tokens(conn)

    renderer_opts = [csrf_token: masked_csrf_token, initial_page?: true]

    handle_page_request(conn_with_csrf_token, page_module, params, renderer_opts)
  end

  @doc """
  Handles the ping HTTP GET request by building HTTP response.
  """
  @spec handle_ping_request(Plug.Conn.t()) :: Plug.Conn.t()
  def handle_ping_request(conn) do
    conn
    |> put_text_response(200, "pong")
    |> Plug.Conn.halt()
  end

  @doc """
  Handles a subsequent page HTTP GET request by building HTTP response.
  Exracts page parameters from the query string.

  ## Parameters

    * `conn` - The Plug.Conn struct representing the HTTP request
    * `page_module` - The page module to render

  ## Returns

  The updated and halted Plug.Conn struct with the rendered HTML and applied cookies.
  """
  @spec handle_subsequent_page_request(Plug.Conn.t(), module) :: Plug.Conn.t()
  def handle_subsequent_page_request(initial_conn, page_module) do
    conn = PlugConnUtils.init_conn(initial_conn)

    params =
      conn
      |> Plug.Conn.fetch_query_params()
      |> Map.get(:query_params)
      |> Page.cast_params(page_module)

    handle_page_request(conn, page_module, params, initial_page?: false)
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

  defp get_csrf_token_from_header(conn) do
    case Plug.Conn.get_req_header(conn, "x-csrf-token") do
      [token] when is_binary(token) and token != "" -> {:ok, token}
      _fallback -> :error
    end
  end

  defp get_csrf_token_from_session(conn) do
    case Plug.Conn.get_session(conn, CSRFProtection.session_key()) do
      token when is_binary(token) -> {:ok, token}
      _fallback -> :error
    end
  end

  # sobelow_skip ["XSS.HTML"]
  defp handle_page_request(conn, page_module, params, renderer_opts) do
    # TODO: uncomment when standalone Hologram is supported
    # {conn_with_session, _session_id} = Session.init(conn)

    server_struct = Server.from(conn)

    {html, _component_registry, updated_server_struct} =
      Renderer.render_page(page_module, params, server_struct, renderer_opts)

    conn
    |> apply_session_ops(updated_server_struct.__meta__.session_ops)
    |> apply_cookie_ops(updated_server_struct.__meta__.cookie_ops)
    |> put_html_response(200, html)
    |> Plug.Conn.halt()
  end

  defp process_command_result(command_result, server_struct, default_target) do
    case command_result do
      %Server{next_action: %Action{target: nil} = action} = updated_server_struct ->
        {updated_server_struct, %{action | target: default_target}}

      %Server{next_action: action} = updated_server_struct ->
        {updated_server_struct, action}

      _fallback ->
        {server_struct, nil}
    end
  end

  defp put_html_response(conn, status, html) do
    conn
    |> Plug.Conn.send_resp(status, html)
    |> Plug.Conn.put_resp_header("content-type", "text/html; charset=utf-8")
  end

  defp put_json_response(conn, status, data) do
    json = Jason.encode!(data)

    conn
    |> Plug.Conn.send_resp(status, json)
    |> Plug.Conn.put_resp_header("content-type", "application/json")
  end

  defp put_text_response(conn, status, text) do
    conn
    |> Plug.Conn.send_resp(status, text)
    |> Plug.Conn.put_resp_header("content-type", "text/plain; charset=utf-8")
  end

  defp same_site_to_string(:lax), do: "Lax"

  defp same_site_to_string(:none), do: "None"

  defp same_site_to_string(:strict), do: "Strict"

  defp same_site_to_string(nil), do: nil

  defp validate_csrf_token(conn) do
    with {:ok, client_token} <- get_csrf_token_from_header(conn),
         {:ok, session_token} <- get_csrf_token_from_session(conn),
         true <- CSRFProtection.validate_token(session_token, client_token) do
      true
    else
      _fallback -> false
    end
  end
end
