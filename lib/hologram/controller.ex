defmodule Hologram.Controller do
  @moduledoc false

  require Logger

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Page
  alias Hologram.Realtime
  alias Hologram.Realtime.Receipt
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Runtime.Deserializer
  alias Hologram.Runtime.PlugConnUtils
  alias Hologram.Runtime.Session
  alias Hologram.Server
  alias Hologram.Template.Renderer
  alias Phoenix.Controller

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
        [{key, URI.decode(value)} | acc]

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
    conn =
      initial_conn
      |> PlugConnUtils.init_conn()
      |> Session.init()

    if validate_csrf_token(conn) do
      payload =
        conn.body_params
        |> Map.get("_json")
        |> Deserializer.deserialize()

      %{
        instance_id: instance_id,
        module: module,
        name: name,
        params: params,
        target: target
      } = payload

      bindings = SubscriptionRegistry.bindings_of(instance_id) || %{}

      server_struct = %{
        Server.from(conn)
        | cid: target,
          instance_id: instance_id,
          subscriptions: Map.keys(bindings)
      }

      command_result = module.command(name, params, server_struct)

      {processed_server_struct, next_action} =
        process_command_result(command_result, server_struct, target)

      # Apply subscription deltas before flushing broadcasts so a registry
      # failure (GenServer.call timeout) leaves no half-done state.
      # flush_broadcasts is effectively infallible, so once apply succeeds both
      # side effects land.
      {sub_receipts, sub_drops} = apply_subscription_deltas(processed_server_struct)

      # Snapshot self-echoes before flush_broadcasts/1 clears the queue.
      self_echoes = Realtime.get_self_echoes(processed_server_struct)

      flushed_server_struct = Realtime.flush_broadcasts(processed_server_struct)

      {encode_status, encoded_next_action} = Encoder.encode_term(next_action)
      command_status = if encode_status == :ok, do: 1, else: 0

      {:ok, encoded_self_echoes} = Encoder.encode_term(self_echoes)
      {:ok, encoded_sub_receipts} = Encoder.encode_term(sub_receipts)
      {:ok, encoded_sub_drops} = Encoder.encode_term(sub_drops)

      conn
      |> apply_session_ops(flushed_server_struct.__meta__.session_ops)
      |> apply_cookie_ops(flushed_server_struct.__meta__.cookie_ops)
      |> Controller.json([
        command_status,
        encoded_next_action,
        encoded_self_echoes,
        encoded_sub_receipts,
        encoded_sub_drops
      ])
      |> Plug.Conn.halt()
    else
      Logger.warning("CSRF token validation failed")

      conn
      |> Plug.Conn.put_status(403)
      |> Controller.text("Forbidden")
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

    instance_id = UUID.uuid4()

    renderer_opts = [
      csrf_token: masked_csrf_token,
      initial_page?: true,
      instance_id: instance_id
    ]

    handle_page_request(conn_with_csrf_token, page_module, params, renderer_opts)
  end

  # Public for tests so they can drive a page render with a known instance_id
  # without going through the auto-generating `handle_initial_page_request/2`.
  @doc false
  # sobelow_skip ["XSS.HTML"]
  @spec handle_page_request(Plug.Conn.t(), module, map, keyword) :: Plug.Conn.t()
  def handle_page_request(initial_conn, page_module, params, renderer_opts) do
    conn = Session.init(initial_conn)

    server_struct = %{
      Server.from(conn)
      | cid: "page",
        instance_id: renderer_opts[:instance_id]
    }

    {html, _component_registry, rendered_server_struct} =
      Renderer.render_page(page_module, params, server_struct, renderer_opts)

    # Transition subscriptions before flushing broadcasts so a registry failure
    # (GenServer.call timeout) leaves no half-done state. flush_broadcasts is
    # effectively infallible, so once transition succeeds both side effects land.
    transition_subscriptions(rendered_server_struct)

    # Snapshot self-echoes before flush_broadcasts/1 clears the queue. The
    # renderer leaves `$SELF_ECHOES_JS_PLACEHOLDER` in the HTML on purpose so
    # this Realtime-domain computation lives in the controller; substituting
    # back into HTML here keeps the renderer Realtime-agnostic.
    self_echoes = Realtime.get_self_echoes(rendered_server_struct)

    flushed_server_struct = Realtime.flush_broadcasts(rendered_server_struct)

    html_with_self_echoes = Renderer.interpolate_self_echoes_js(html, self_echoes)

    conn
    |> apply_session_ops(flushed_server_struct.__meta__.session_ops)
    |> apply_cookie_ops(flushed_server_struct.__meta__.cookie_ops)
    |> Controller.html(html_with_self_echoes)
    |> Plug.Conn.halt()
  end

  @doc """
  Handles the ping HTTP GET request by building HTTP response.
  """
  @spec handle_ping_request(Plug.Conn.t()) :: Plug.Conn.t()
  def handle_ping_request(conn) do
    conn
    |> Controller.text("pong")
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

  defp apply_subscription_deltas(%Server{__meta__: %{subscription_ops: ops}}) when ops == %{},
    do: {[], []}

  defp apply_subscription_deltas(%Server{__meta__: %{subscription_ops: ops}} = server) do
    adds = for {key, :put} <- ops, do: key
    drops = for {key, :delete} <- ops, do: key

    {actually_added, actually_dropped} =
      SubscriptionRegistry.apply_deltas(server.instance_id, adds, drops, server.user_id)

    {build_receipts(actually_added, server), actually_dropped}
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

  defp build_receipts(add_keys, server) do
    Enum.map(add_keys, fn {channel, cid} ->
      {channel, cid, Receipt.issue(channel, cid, server.instance_id, server.user_id)}
    end)
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

  defp same_site_to_string(:lax), do: "Lax"

  defp same_site_to_string(:none), do: "None"

  defp same_site_to_string(:strict), do: "Strict"

  defp same_site_to_string(nil), do: nil

  # Called after a successful page render. Reconciles the registry's binding
  # set for this instance against the union of `put_subscription` calls
  # accumulated across the page-render tree (page + layout + component init/3).
  # `client_supplied_keys` is `[]` for the initial render. `authorizing_user_id`
  # is `nil` until the auth gate is wired.
  #
  # TODO: thread the client's prior subscription keys + instance_id through for
  # subsequent navigations; once that's wired, instance_id is always non-nil and
  # the nil clause below becomes dead code.
  defp transition_subscriptions(server)

  defp transition_subscriptions(%Server{instance_id: nil}), do: :ok

  defp transition_subscriptions(%Server{instance_id: instance_id, subscriptions: subscriptions}) do
    SubscriptionRegistry.transition(instance_id, subscriptions, [], nil)
    :ok
  end

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
