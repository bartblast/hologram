defmodule Hologram.Runtime.MessageHandler do
  @moduledoc false

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias Hologram.Runtime.Connection

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
  """
  @spec handle(String.t(), any, Connection.state()) :: {String.t(), any(), Connection.state()}
  def handle(message_type, message_payload, connection_state)

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
end
