defmodule Hologram.Connection do
  def init(http_conn) do
    {:ok, http_conn}
  end

  def handle_in({"ping", [opcode: :text]}, http_conn) do
    {:reply, :ok, {:text, "pong"}, http_conn}
  end

  # TODO: remove
  def handle_in(arg, http_conn) do
    IO.inspect(arg)
    {:reply, :ok, {:text, "placeholder"}, http_conn}
  end
end
