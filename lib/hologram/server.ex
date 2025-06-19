defmodule Hologram.Server do
  @behaviour WebSock

  alias Hologram.Component.Action

  defstruct cookies: %{}, next_action: nil, session: %{}

  @type t :: %__MODULE__{
          cookies: %{atom => any},
          next_action: Action.t() | nil,
          session: %{atom => any}
        }

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
    IO.inspect(arg)
    {:reply, :ok, {:text, "placeholder"}, http_conn}
  end

  @impl WebSock
  def handle_info(_arg, http_conn) do
    {:ok, http_conn}
  end
end
