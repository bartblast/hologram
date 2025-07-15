defmodule Hologram.Runtime.MessageHandler do
  @moduledoc false

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Commons.BooleanUtils
  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias Hologram.Runtime.Connection
  alias Hologram.Runtime.CookieStore
  alias Hologram.Server
  alias Hologram.Template.Renderer

  @doc """
  Handles various types of WebSocket messages from the client runtime.

  ## Parameters
    - `type` - String identifying the type of message to handle
    - `payload` - Message-specific payload (varies by message type)
    - `connection_state` - Connection state

  ## Returns
  A tuple containing the response type and payload, and new connection state.

  ## Examples

      iex> MessageHandler.handle("ping", nil, connection_state)
      {"pong", :__no_payload__, connection_state}

      iex> MessageHandler.handle("page", MyPageModule, connection_state)
      {"reply", "<html>...</html>", new_connection_state}
  """
  @spec handle(String.t(), any, Connection.state()) :: {String.t(), any(), Connection.state()}
  def handle(message_type, message_payload, connection_state)

  def handle("command", payload, connection_state) do
    %{module: module, name: name, params: params, target: target} = payload
    %{cookie_store: cookie_store} = connection_state

    server_struct = Server.from(cookie_store)

    command_result = module.command(name, params, server_struct)

    next_action =
      case command_result do
        %Server{next_action: action = %Action{target: nil}} ->
          %{action | target: target}

        %Server{next_action: action} ->
          action

        _fallback ->
          nil
      end

    new_cookie_store = maybe_merge_cookie_ops(cookie_store, command_result)

    # TODO: handle session

    {encode_status, encoded_next_action} = Encoder.encode_term(next_action)
    command_status = if encode_status == :ok, do: 1, else: 0

    sync_cookies_flag =
      new_cookie_store
      |> CookieStore.has_pending_ops?()
      |> BooleanUtils.to_integer()

    new_connection_state = %{connection_state | cookie_store: new_cookie_store}

    {"reply", [command_status, encoded_next_action, sync_cookies_flag], new_connection_state}
  end

  def handle("page", payload, connection_state) do
    %{cookie_store: cookie_store} = connection_state

    server_struct = Server.from(cookie_store)
    opts = [initial_page?: false]

    {html, _component_registry, new_server_struct} =
      case payload do
        {page_module, params} ->
          Renderer.render_page(page_module, params, server_struct, opts)

        page_module ->
          Renderer.render_page(page_module, %{}, server_struct, opts)
      end

    new_cookie_store = maybe_merge_cookie_ops(cookie_store, new_server_struct)

    # TODO: handle session

    new_connection_state = %{connection_state | cookie_store: new_cookie_store}

    {"reply", html, new_connection_state}
  end

  def handle("page_bundle_path", page_module, connection_state) do
    page_bundle_path =
      page_module
      |> PageDigestRegistry.lookup()
      |> RouterHelpers.page_bundle_path()

    {"reply", page_bundle_path, connection_state}
  end

  def handle("ping", nil, connection_state) do
    {"pong", :__no_payload__, connection_state}
  end

  defp maybe_merge_cookie_ops(cookie_store, maybe_server_struct) do
    case maybe_server_struct do
      %Server{} = server_struct ->
        if Server.has_cookie_ops?(server_struct) do
          CookieStore.merge_pending_ops(cookie_store, Server.get_cookie_ops(server_struct))
        else
          cookie_store
        end

      _fallback ->
        cookie_store
    end
  end
end
