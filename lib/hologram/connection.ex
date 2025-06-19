defmodule Hologram.Connection do
  @behaviour WebSock

  @impl WebSock
  def init(http_conn) do
    {:ok, http_conn}
  end

  @impl WebSock
  def handle_in({"ping", [opcode: :text]}, http_conn) do
    {:reply, :ok, {:text, "pong"}, http_conn}
  end

  # TODO: remove
  @impl WebSock
  def handle_in(arg, http_conn) do
    # credo:disable-for-next-line Credo.Check.Warning.IoInspect
    IO.inspect(arg)
    {:reply, :ok, {:text, "placeholder"}, http_conn}
  end

  @impl WebSock
  def handle_info(_arg, http_conn) do
    {:ok, http_conn}
  end
end
