defmodule Hologram.Runtime.Connection do
  @moduledoc false

  @behaviour WebSock

  alias Hologram.Assets.PageDigestRegistry
  alias Hologram.Router.Helpers, as: RouterHelpers
  alias Hologram.Runtime.Deserializer

  @type state :: %{plug_conn: Plug.Conn.t()}

  @impl WebSock
  def init(plug_conn) do
    if Hologram.env() == :dev do
      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")
    end

    connection_id = UUID.uuid4()

    state = %{
      connection_id: connection_id,
      plug_conn: plug_conn
    }

    {:ok, state}
  end

  @impl WebSock
  def handle_in({message, [opcode: :text]}, state) do
    {message_type, message_payload, correlation_id} = decode(message)

    {reply_type, reply_payload, new_state} = handle_message(message_type, message_payload, state)
    reply = encode(reply_type, reply_payload, correlation_id)

    {:reply, :ok, {:text, reply}, new_state}
  end

  @impl WebSock
  def handle_info({:compilation_error, output}, state) do
    message = encode("compilation_error", output, nil)
    {:push, {:text, message}, state}
  end

  @impl WebSock
  def handle_info(:reload, state) do
    message = encode("reload", :__no_payload__, nil)
    {:push, {:text, message}, state}
  end

  @impl WebSock
  def handle_info(_arg, state) do
    {:ok, state}
  end

  defp decode(message) do
    case Jason.decode!(message) do
      [type, payload, correlation_id] ->
        {type, Deserializer.deserialize(payload), correlation_id}

      type ->
        {type, nil, nil}
    end
  end

  defp encode(type, :__no_payload__, nil) do
    Jason.encode!(type)
  end

  defp encode(type, payload, nil) do
    Jason.encode!([type, payload])
  end

  defp encode(type, payload, correlation_id) do
    Jason.encode!([type, payload, correlation_id])
  end

  defp handle_message("page_bundle_path", page_module, connection_state) do
    page_bundle_path =
      page_module
      |> PageDigestRegistry.lookup()
      |> RouterHelpers.page_bundle_path()

    {"reply", page_bundle_path, connection_state}
  end

  defp handle_message("ping", nil, connection_state) do
    {"pong", :__no_payload__, connection_state}
  end
end
