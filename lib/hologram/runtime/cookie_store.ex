defmodule Hologram.Runtime.CookieStore do
  @moduledoc false

  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CookieStore
  alias Hologram.Runtime.PlugConnUtils

  defstruct persisted: %{}, pending: %{}

  @type t :: %__MODULE__{
          persisted: %{String.t() => Cookie.op() | String.t()},
          pending: %{String.t() => Cookie.op()}
        }

  @doc """
  Returns a map of effective cookies from the cookie store.

  Values from cookie operations with higher timestamps take precedence over
  already persisted cookies with smaller timestamps. Deleted cookies are excluded.
  Plain string values from persisted cookies are treated as having timestamp 0.
  Cookies with nil values are included in the result.

  ## Examples

      iex> store = %CookieStore{
      ...>   persisted: %{"key_1" => "value_1", "key_2" => {:put, 100, %Cookie{value: "old_value"}}},
      ...>   pending: %{
      ...>     "key_2" => {:put, 200, %Cookie{value: "new_value"}}, 
      ...>     "key_3" => {:delete, 150},
      ...>     "key_4" => {:put, 180, %Cookie{value: nil}}
      ...>   }
      ...> }
      iex> CookieStore.effective_cookies(store)
      %{"key_1" => "value_1", "key_2" => "new_value", "key_4" => nil}
  """
  @spec effective_cookies(t) :: %{String.t() => any}
  def effective_cookies(%CookieStore{persisted: persisted, pending: pending}) do
    persisted_keys =
      persisted
      |> Map.keys()
      |> MapSet.new()

    pending_keys =
      pending
      |> Map.keys()
      |> MapSet.new()

    all_keys = MapSet.union(persisted_keys, pending_keys)

    for key <- all_keys, reduce: %{} do
      acc ->
        case fetch_latest_value(key, persisted, pending) do
          {:ok, value} -> Map.put(acc, key, value)
          :error -> acc
        end
    end
  end

  @doc """
  Creates a new cookie store from a Plug.Conn struct.

  Extracts cookies from the given connection and stores them as persisted cookies
  in the returned cookie store. The pending cookies map will be empty.
  The Hologram session cookie (hologram_session) is excluded.

  ## Parameters

    * `conn` - A Plug.Conn struct containing cookies to extract

  ## Examples

      iex> conn = %Plug.Conn{req_headers: [{"cookie", "user_id=abc123; theme=dark"}]}
      iex> store = CookieStore.from(conn)
      iex> store.persisted
      %{"user_id" => "abc123", "theme" => "dark"}
      iex> store.pending
      %{}
  """
  @spec from(Plug.Conn.t()) :: t
  def from(%Plug.Conn{} = conn) do
    %__MODULE__{
      persisted: PlugConnUtils.extract_cookies(conn)
    }
  end

  # Fetch the latest value for a key based on timestamp precedence
  # Returns {:ok, value} for existing cookies (value may be nil)
  # Returns :error for deleted or non-existent cookies
  defp fetch_latest_value(key, persisted, pending) do
    persisted_op = Map.get(persisted, key)
    pending_op = Map.get(pending, key)

    ops =
      []
      |> maybe_collect_op(persisted_op)
      |> maybe_collect_op(pending_op)

    # Sort by timestamp (highest first) and get the most recent op
    case Enum.sort_by(ops, &elem(&1, 1), :desc) do
      [] -> :error
      [{:put, _timestamp, value} | _rest] -> {:ok, value}
      [{:delete, _timestamp} | _rest] -> :error
    end
  end

  defp maybe_collect_op(ops, op) do
    case op do
      nil ->
        ops

      # Treat plain string values as timestamp 0 (this will happen only for persisted entries)
      value when is_binary(value) ->
        [{:put, 0, value} | ops]

      {:put, timestamp, %Cookie{value: value}} ->
        [{:put, timestamp, value} | ops]

      {:delete, _timestamp} = op ->
        [op | ops]
    end
  end
end
