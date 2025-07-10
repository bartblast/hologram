defmodule Hologram.Runtime.Connection do
  @behaviour WebSock

  alias Hologram.Runtime.CookieStore
  alias Hologram.Runtime.Deserializer
  alias Hologram.Runtime.MessageHandler
  alias Hologram.Server

  @impl WebSock
  def init(plug_conn) do
    if Hologram.env() == :dev do
      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")
    end

    state = %{
      cookie_store: CookieStore.from(plug_conn),
      plug_conn: plug_conn
    }

    {:ok, state}
  end

  @impl WebSock
  def handle_in({message, [opcode: :text]}, state) do
    {message_type, message_payload, correlation_id} = decode(message)
    {reply_type, reply_payload} = MessageHandler.handle(message_type, message_payload, %Server{})
    reply = encode(reply_type, reply_payload, correlation_id)

    {:reply, :ok, {:text, reply}, state}
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

      # Not needed (yet)
      # [type, payload] ->
      #   {type, Deserializer.deserialize(payload), nil}

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
end
