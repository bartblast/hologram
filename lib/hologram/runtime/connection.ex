defmodule Hologram.Runtime.Connection do
  @behaviour WebSock

  alias Hologram.Runtime.CookieStore
  alias Hologram.Runtime.Deserializer
  alias Hologram.Runtime.MessageHandler

  @type state :: %{cookie_store: CookieStore.t(), plug_conn: Plug.Conn.t()}

  @impl WebSock
  def init(plug_conn) do
    if Hologram.env() == :dev do
      Phoenix.PubSub.subscribe(Hologram.PubSub, "hologram_live_reload")
    end

    connection_id = UUID.uuid4()

    context = gproc_context(Hologram.env())
    :gproc.reg({:n, context, {:hologram_connection, connection_id}})

    state = %{
      connection_id: connection_id,
      cookie_store: CookieStore.from(plug_conn),
      plug_conn: plug_conn
    }

    {:ok, state}
  end

  @impl WebSock
  def handle_in({message, [opcode: :text]}, state) do
    {message_type, message_payload, correlation_id} = decode(message)

    {reply_type, reply_payload, new_state} =
      MessageHandler.handle(message_type, message_payload, state)

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

  @impl WebSock
  def terminate(_reason, state) do
    context = gproc_context(Hologram.env())
    :gproc.unreg({:n, context, {:hologram_connection, state.connection_id}})

    :ok
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

  defp gproc_context(:dev), do: :l
  defp gproc_context(:test), do: :l
  defp gproc_context(_env), do: :g
end
