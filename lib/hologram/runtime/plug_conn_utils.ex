defmodule Hologram.Runtime.PlugConnUtils do
  alias Hologram.Runtime.Cookie

  @doc """
  Extracts cookies from the Plug.Conn struct.

  Each cookie value is decoded using Cookie.decode/1,
  which handles both Hologram-encoded cookies (with "%H" prefix) and plain
  string cookies.

  The "hologram_session" cookie is automatically excluded
  from the cookies map.

  ## Parameters

    * `conn` - A Plug connection struct
  """
  @spec extract_cookies(Plug.Conn.t()) :: %{String.t() => any}
  def extract_cookies(conn) do
    conn
    |> Map.fetch!(:cookies)
    |> Map.delete("hologram_session")
    |> Enum.map(fn {key, value} -> {key, Cookie.decode(value)} end)
    |> Enum.into(%{})
  end

  @doc """
  Initializes the given Plug.Conn by fetching cookies and session data.
  This ensures that both cookies and session are available for subsequent operations on the connection.
  """
  @spec init_conn(Plug.Conn.t()) :: Plug.Conn.t()
  def init_conn(conn) do
    conn
    |> Plug.Conn.fetch_cookies()
    |> Plug.Conn.fetch_session()
  end
end
