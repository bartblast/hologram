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

  ## Examples

      iex> conn = %Plug.Conn{req_headers: [{"cookie", "user_id=abc123; hologram_session=xyz789"}]}
      iex> extract_cookies(conn)
      %{"user_id" => "abc123"}

      iex> # Hologram-encoded cookie is decoded to original term
      iex> conn = %Plug.Conn{req_headers: [{"cookie", "settings=%Hg3QAAAABdwNrZXltAAAABXZhbHVl"}]}
      iex> extract_cookies(conn)
      %{"settings" => %{key: "value"}}
  """
  @spec extract_cookies(Plug.Conn.t()) :: %{String.t() => any}
  def extract_cookies(conn) do
    conn
    |> Plug.Conn.fetch_cookies()
    |> Map.fetch!(:cookies)
    |> Map.delete("hologram_session")
    |> Enum.map(fn {key, value} -> {key, Cookie.decode(value)} end)
    |> Enum.into(%{})
  end
end
