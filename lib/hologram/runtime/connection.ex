defmodule Hologram.Runtime.Connection do
  @behaviour WebSock

  alias Hologram.Runtime.Deserializer
  alias Hologram.Runtime.MessageHandler

  @impl WebSock
  def init(http_conn) do
    {:ok, http_conn}
  end

  @impl WebSock
  def handle_in({message, [opcode: :text]}, state) do
    {message_type, message_payload, correlation_id} = decode(message)
    {reply_type, reply_payload} = MessageHandler.handle(message_type, message_payload)
    reply = encode(reply_type, reply_payload, correlation_id)

    {:reply, :ok, {:text, reply}, state}
  end

  @impl WebSock
  def handle_info(_arg, state) do
    {:ok, state}
  end

  defp decode(message) do
    case Jason.decode!(message) do
      [type, payload, correlation_id] ->
        {type, Deserializer.deserialize(payload), correlation_id}

      [type, payload] ->
        {type, Deserializer.deserialize(payload), nil}

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
