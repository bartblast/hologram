defmodule Hologram.Controller do
  @moduledoc false

  require Logger

  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Page
  alias Hologram.Realtime
  alias Hologram.Realtime.Handshake
  alias Hologram.Realtime.Receipt
  alias Hologram.Realtime.SubscriptionRegistry
  alias Hologram.Realtime.Tombstone
  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CSRFProtection
  alias Hologram.Runtime.Deserializer
  alias Hologram.Runtime.PlugConnUtils
  alias Hologram.Runtime.Session
  alias Hologram.Server
  alias Hologram.Server.Middleware
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

      if caller_owns_instance_id?(conn, instance_id) do
        handle_validated_command_request(conn, instance_id, module, name, params, target)
      else
        Logger.warning("instance_id cross-check failed")

        conn
        |> Plug.Conn.put_status(403)
        |> Controller.text("Forbidden")
        |> Plug.Conn.halt()
      end
    else
      Logger.warning("CSRF token validation failed")

      conn
      |> Plug.Conn.put_status(403)
      |> Controller.text("Forbidden")
      |> Plug.Conn.halt()
    end
  end

  # Returns true when the registry has no entry for the `instance_id` (the
  # instance hasn't attached yet, or its SSE process died and was GC'd) or
  # when the entry's recorded `{session_id, user_id}` matches the caller's
  # current session. Returns false when an entry exists but its identity
  # doesn't match - the caller is using an `instance_id` they didn't
  # establish (forgery, or post-logout stale state).
  defp caller_owns_instance_id?(conn, instance_id) do
    case SubscriptionRegistry.identity_of(instance_id) do
      nil ->
        true

      registry_identity ->
        registry_identity == {Session.get_session_id(conn), Session.get_user_id(conn)}
    end
  end

  defp handle_validated_command_request(conn, instance_id, module, name, params, target) do
    bindings = SubscriptionRegistry.bindings_of(instance_id) || %{}

    target_subscriptions =
      for {{_channel, cid} = key, _user_id} <- bindings, cid == target, do: key

    server_struct = %{
      Server.from(conn)
      | cid: target,
        instance_id: instance_id,
        subscriptions: target_subscriptions
    }

    middleware_server_struct = Middleware.run(server_struct, module.middleware(server_struct))

    if middleware_server_struct.status do
      # Middleware produced a terminal response - skip the command and send it,
      # still applying the decorations accumulated by the steps that ran.
      conn
      |> apply_session_ops(middleware_server_struct.__meta__.session_ops)
      |> apply_cookie_ops(middleware_server_struct.__meta__.cookie_ops)
      |> maybe_persist_user_id(server_struct, middleware_server_struct)
      |> send_response(middleware_server_struct)
      |> Plug.Conn.halt()
    else
      command_result = module.command(name, params, middleware_server_struct)

      {processed_server_struct, next_action} =
        process_command_result(command_result, middleware_server_struct, target)

      # Apply subscription deltas before flushing broadcasts so a registry
      # failure (GenServer.call timeout) leaves no half-done state.
      # flush_broadcasts is effectively infallible, so once apply succeeds both
      # side effects land.
      {sub_receipt_adds, sub_receipt_drops} = apply_subscription_deltas(processed_server_struct)

      Realtime.maybe_announce_identity_change(server_struct, processed_server_struct)

      # Snapshot self-echoes before flush_broadcasts/1 clears the queue. Self-echoes
      # reach every component on the originating instance subscribed to the
      # broadcast channel, so they are materialized against the instance-wide
      # subscription set rather than the cid-scoped server.subscriptions.
      self_echoes =
        Realtime.get_self_echoes(
          processed_server_struct,
          instance_subscriptions(bindings, processed_server_struct.__meta__.subscription_ops)
        )

      flushed_server_struct = Realtime.flush_broadcasts(processed_server_struct)

      {encode_status, encoded_next_action} = Encoder.encode_term(next_action)
      command_status = if encode_status == :ok, do: 1, else: 0

      {:ok, encoded_self_echoes} = Encoder.encode_term(self_echoes)
      {:ok, encoded_sub_receipt_adds} = Encoder.encode_term(sub_receipt_adds)
      {:ok, encoded_sub_receipt_drops} = Encoder.encode_term(sub_receipt_drops)

      conn
      |> apply_session_ops(flushed_server_struct.__meta__.session_ops)
      |> apply_cookie_ops(flushed_server_struct.__meta__.cookie_ops)
      |> maybe_persist_user_id(server_struct, flushed_server_struct)
      |> Controller.json(%{
        action: encoded_next_action,
        selfEchoes: encoded_self_echoes,
        status: command_status,
        subReceiptAdds: encoded_sub_receipt_adds,
        subReceiptDrops: encoded_sub_receipt_drops
      })
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

    handle_page_request(conn_with_csrf_token, page_module, params, [], renderer_opts)
  end

  # Public for tests so they can drive a page render with a known instance_id
  # without going through the auto-generating `handle_initial_page_request/2`.
  @doc false
  # sobelow_skip ["XSS.HTML"]
  @spec handle_page_request(Plug.Conn.t(), module, map, [{any, String.t()}], keyword) ::
          Plug.Conn.t()
  def handle_page_request(
        initial_conn,
        page_module,
        params,
        client_claimed_sub_keys,
        renderer_opts
      ) do
    conn = Session.init(initial_conn)

    server_struct = %{
      Server.from(conn)
      | cid: "page",
        instance_id: renderer_opts[:instance_id]
    }

    middleware_server_struct =
      Middleware.run(server_struct, page_module.middleware(server_struct))

    if middleware_server_struct.status do
      # Middleware produced a terminal response - skip the render and send it,
      # still applying the decorations accumulated by the steps that ran.
      conn
      |> apply_session_ops(middleware_server_struct.__meta__.session_ops)
      |> apply_cookie_ops(middleware_server_struct.__meta__.cookie_ops)
      |> maybe_persist_user_id(server_struct, middleware_server_struct)
      |> send_response(middleware_server_struct)
      |> Plug.Conn.halt()
    else
      {rendered_html, _component_registry, rendered_server_struct} =
        Renderer.render_page(page_module, params, middleware_server_struct, renderer_opts)

      # Transition subscriptions before flushing broadcasts so a registry failure
      # (GenServer.call timeout) leaves no half-done state. flush_broadcasts is
      # effectively infallible, so once transition succeeds both side effects land.
      {sub_receipt_adds, sub_receipt_drops} =
        transition_subscriptions(rendered_server_struct, client_claimed_sub_keys)

      Realtime.maybe_announce_identity_change(server_struct, rendered_server_struct)

      # Snapshot self-echoes before flush_broadcasts/1 clears the queue. The
      # renderer leaves `$SELF_ECHOES_JS_PLACEHOLDER` in the HTML on purpose so
      # this Realtime-domain computation lives in the controller; substituting
      # back into HTML here keeps the renderer Realtime-agnostic.
      self_echoes =
        Realtime.get_self_echoes(rendered_server_struct, rendered_server_struct.subscriptions)

      flushed_server_struct = Realtime.flush_broadcasts(rendered_server_struct)

      final_html =
        rendered_html
        |> Renderer.interpolate_self_echoes_js(self_echoes)
        |> Renderer.interpolate_sub_receipt_adds_js(sub_receipt_adds)
        |> Renderer.interpolate_sub_receipt_drops_js(sub_receipt_drops)

      conn
      |> apply_session_ops(flushed_server_struct.__meta__.session_ops)
      |> apply_cookie_ops(flushed_server_struct.__meta__.cookie_ops)
      |> maybe_persist_user_id(server_struct, flushed_server_struct)
      |> Controller.html(final_html)
      |> Plug.Conn.halt()
    end
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
  Handles the SSE handshake HTTP POST request. Runs the auth gate, mints a
  fresh `handshake_id`, stashes the validated bindings bound to the client's
  identity tuple, and returns the `handshake_id` for the client to use when
  opening the EventSource.
  """
  @spec handle_sse_handshake_request(Plug.Conn.t()) :: Plug.Conn.t()
  def handle_sse_handshake_request(initial_conn) do
    conn = PlugConnUtils.init_conn(initial_conn)

    case Session.get_session_id(conn) do
      nil ->
        conn
        |> Plug.Conn.send_resp(401, "Unauthorized")
        |> Plug.Conn.halt()

      session_id ->
        current_user_id = Session.get_user_id(conn)

        %{instance_id: instance_id, receipts: receipts} =
          conn.body_params
          |> Map.get("_json")
          |> Deserializer.deserialize()

        {validated_bindings, refreshed_receipts} =
          verify_and_refresh_receipts(receipts, instance_id, session_id, current_user_id)

        handshake_id = UUID.uuid4()
        expires_at = System.system_time(:millisecond) + Handshake.stash_ttl_ms()

        Handshake.insert(
          handshake_id,
          validated_bindings,
          {instance_id, session_id, current_user_id},
          expires_at
        )

        {:ok, encoded_refreshed_receipts} = Encoder.encode_term(refreshed_receipts)

        conn
        |> Controller.json(%{
          handshakeId: handshake_id,
          refreshedReceipts: encoded_refreshed_receipts
        })
        |> Plug.Conn.halt()
    end
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

    {instance_id, client_claimed_sub_keys} = extract_page_request_payload(conn)

    params =
      conn
      |> Plug.Conn.fetch_query_params()
      |> Map.get(:query_params)
      |> Page.cast_params(page_module)

    handle_page_request(
      conn,
      page_module,
      params,
      client_claimed_sub_keys,
      initial_page?: false,
      instance_id: instance_id
    )
  end

  @doc """
  Sends the terminal response built from the server struct's response fields.

  Merges `response_headers` onto the connection and sends `status` with `response_body`
  (an empty body when `response_body` is `nil`).
  """
  @spec send_response(Plug.Conn.t(), Server.t()) :: Plug.Conn.t()
  def send_response(conn, server) do
    conn
    |> Plug.Conn.merge_resp_headers(Map.to_list(server.response_headers))
    |> Plug.Conn.send_resp(server.status, server.response_body || "")
  end

  @doc false
  @spec verify_and_refresh_receipts([String.t()], String.t(), term | nil, term | nil) ::
          {[{{any, String.t()}, term | nil}], [{any, String.t(), String.t()}]}
  def verify_and_refresh_receipts(receipts, instance_id, session_id, current_user_id) do
    receipts
    |> Enum.flat_map(fn token ->
      case Receipt.verify(token) do
        {:ok, %Receipt{instance_id: ^instance_id, user_id: authorizing_user_id} = receipt}
        when is_nil(authorizing_user_id) or authorizing_user_id == current_user_id ->
          refresh_unless_tombstoned(receipt, instance_id, session_id, authorizing_user_id)

        _other ->
          []
      end
    end)
    |> Enum.unzip()
  end

  defp apply_subscription_deltas(%Server{__meta__: %{subscription_ops: ops}}) when ops == %{},
    do: {[], []}

  defp apply_subscription_deltas(%Server{__meta__: %{subscription_ops: ops}} = server) do
    adds = for {key, :put} <- ops, do: key
    drops = for {key, :delete} <- ops, do: key

    {actually_added, actually_dropped} =
      SubscriptionRegistry.apply_deltas(server.instance_id, adds, drops, server.user_id)

    now = System.system_time(:millisecond)

    Enum.each(actually_dropped, fn {channel, cid} ->
      Tombstone.insert({{:instance, server.instance_id}, channel, cid}, now)
    end)

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

  # Reads the Hologram-serialized JSON body produced by `Client.fetchPage` and
  # pulls out the two fields the page-render path needs from the client:
  # the stable JS-context `instance_id` and the subscription keys the client claims to
  # currently hold in its subscription receipt registry.
  defp extract_page_request_payload(%Plug.Conn{body_params: %{"_json" => json}}) do
    %{instance_id: instance_id, client_claimed_sub_keys: client_claimed_sub_keys} =
      Deserializer.deserialize(json)

    {instance_id, client_claimed_sub_keys}
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

  # Returns the originating instance's full post-handler subscription set: the
  # command-start `bindings` adjusted by this handler's subscription ops. Used to
  # materialize self-echoes, which reach every component on the instance
  # subscribed to the broadcast channel - not only the command's target cid (the
  # scope of `server.subscriptions`).
  defp instance_subscriptions(bindings, subscription_ops) do
    initial_acc =
      bindings
      |> Map.keys()
      |> MapSet.new()

    subscription_ops
    |> Enum.reduce(initial_acc, fn
      {key, :put}, acc -> MapSet.put(acc, key)
      {key, :delete}, acc -> MapSet.delete(acc, key)
    end)
    |> MapSet.to_list()
  end

  # Persists a handler-driven `server.user_id` change into the Phoenix session
  # (the opaque `:hologram_user_id` key) so later requests resolve the new
  # identity. No-op when unchanged, leaving the session - and any Set-Cookie -
  # untouched on the common path. Applied after the handler's own ops so
  # `server.user_id` stays the source of truth for the key.
  defp maybe_persist_user_id(conn, %Server{user_id: user_id}, %Server{user_id: user_id}) do
    conn
  end

  defp maybe_persist_user_id(conn, _pre_server, %Server{user_id: user_id}) do
    Session.put_user_id(conn, user_id)
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

  defp refresh_unless_tombstoned(receipt, instance_id, session_id, authorizing_user_id) do
    if tombstoned?(receipt, instance_id, session_id, authorizing_user_id) do
      []
    else
      fresh_token =
        Receipt.issue(receipt.channel, receipt.cid, instance_id, authorizing_user_id)

      [
        {{{receipt.channel, receipt.cid}, authorizing_user_id},
         {receipt.channel, receipt.cid, fresh_token}}
      ]
    end
  end

  defp same_site_to_string(:lax), do: "Lax"

  defp same_site_to_string(:none), do: "None"

  defp same_site_to_string(:strict), do: "Strict"

  defp same_site_to_string(nil), do: nil

  defp tombstone_at_or_after?(key, threshold) do
    case :ets.lookup(Tombstone.ets_table_name(), key) do
      [{^key, tombstone_at}] -> tombstone_at >= threshold
      [] -> false
    end
  end

  defp tombstoned?(receipt, instance_id, session_id, authorizing_user_id) do
    identities = [
      {:instance, instance_id},
      {:session, session_id},
      {:user, authorizing_user_id}
    ]

    identities
    |> Enum.reject(fn {_kind, id} -> is_nil(id) end)
    |> Enum.any?(fn identity ->
      binding_key = {identity, receipt.channel, receipt.cid}
      channel_key = {identity, receipt.channel}

      tombstone_at_or_after?(binding_key, receipt.created_at) or
        tombstone_at_or_after?(channel_key, receipt.created_at)
    end)
  end

  # Called after a successful page render. Reconciles the registry's binding
  # set for this instance against the union of `put_subscription` calls
  # accumulated across the page-render tree (page + layout + component init/3).
  # `client_claimed_sub_keys` is `[]` for the initial render and the keys the
  # client claims to currently hold for subsequent navigations.
  # `authorizing_user_id` is `nil` until the auth gate is wired.
  #
  # Drops here are intentionally NOT tombstoned (unlike `apply_subscription_deltas/1`,
  # the explicit-removal path). This is the high-frequency cleanup path (every
  # navigation), and a drop means only "the new page didn't re-declare this
  # binding", not an authoritative revocation - tombstoning every navigation
  # would both explode tombstone volume and, via the `created_at` threshold,
  # reject the snapshot-restored receipt a prior page still relies on when the
  # user navigates back. Authoritative removal stays on the explicit-delete
  # path.
  defp transition_subscriptions(server, client_claimed_sub_keys)

  defp transition_subscriptions(%Server{instance_id: nil}, _client_claimed_sub_keys), do: {[], []}

  defp transition_subscriptions(
         %Server{instance_id: instance_id, subscriptions: subscriptions} = server,
         client_claimed_sub_keys
       ) do
    {actually_added, actually_dropped} =
      SubscriptionRegistry.transition(
        instance_id,
        subscriptions,
        client_claimed_sub_keys,
        server.user_id
      )

    {build_receipts(actually_added, server), actually_dropped}
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
