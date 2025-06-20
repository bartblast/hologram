defmodule Hologram.Runtime.Connection do
  @behaviour WebSock

  alias Hologram.Runtime.Decoder
  alias Hologram.Runtime.MessageHandler

  @impl WebSock
  def init(http_conn) do
    {:ok, http_conn}
  end

  @impl WebSock
  def handle_in({"ping", [opcode: :text]}, http_conn) do
    {:reply, :ok, {:text, "pong"}, http_conn}
  end

  @impl WebSock
  def handle_in({message, [opcode: :text]}, http_conn) do
    [type, payload] = Decoder.decode(message)
    {status, body} = MessageHandler.handle(type, payload)
    {:reply, status, {:text, body}, http_conn}
  end

  @impl WebSock
  def handle_info(_arg, http_conn) do
    {:ok, http_conn}
  end
end
