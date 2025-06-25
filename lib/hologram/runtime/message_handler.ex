defmodule Hologram.Runtime.MessageHandler do
  @moduledoc false

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Compiler.Encoder
  alias Hologram.Component.Action
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias Hologram.Server
  alias Hologram.Template.Renderer

  @doc """
  Handles various types of WebSocket messages from the client runtime.

  ## Parameters
    - `type` - String identifying the type of message to handle
    - `payload` - Message-specific payload (varies by message type)
    - `server_struct` - Server state containing server-side data (e.g., cookies, session, next action)

  ## Returns
  A tuple containing the response type and payload.

  ## Examples

      iex> MessageHandler.handle("ping", nil, %Server{})
      {"pong", :__no_payload__}

      iex> MessageHandler.handle("page", MyPageModule, %Server{})
      {"reply", "<html>...</html>"}
  """
  @spec handle(String.t(), any, Server.t()) :: {String.t(), any()}
  def handle("command", payload, server_struct) do
    %{module: module, name: name, params: params, target: target} = payload

    result = module.command(name, params, server_struct)

    # TODO: handle session & cookies
    next_action =
      case result do
        %Server{next_action: action = %Action{target: nil}} ->
          %{action | target: target}

        %Server{next_action: action} ->
          action

        _fallback ->
          nil
      end

    {status_atom, encoded_result} = Encoder.encode_term(next_action)
    status_integer = if status_atom == :ok, do: 1, else: 0

    {"reply", [status_integer, encoded_result]}
  end

  def handle("page", payload, server_struct) do
    opts = [initial_page?: false]

    {html, _component_registry, _mutated_server_struct} =
      case payload do
        {page_module, params} ->
          Renderer.render_page(page_module, params, server_struct, opts)

        page_module ->
          Renderer.render_page(page_module, %{}, server_struct, opts)
      end

    {"reply", html}
  end

  def handle("page_bundle_path", page_module, _server_struct) do
    page_bundle_path =
      page_module
      |> PageDigestRegistry.lookup()
      |> RouterHelpers.page_bundle_path()

    {"reply", page_bundle_path}
  end

  def handle("ping", nil, _server_struct) do
    {"pong", :__no_payload__}
  end
end
