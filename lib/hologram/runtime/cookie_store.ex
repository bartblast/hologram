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
  def effective_cookies(%CookieStore{} = cookie_store) do
    persisted_keys =
      cookie_store.persisted
      |> Map.keys()
      |> MapSet.new()

    pending_keys =
      cookie_store.pending
      |> Map.keys()
      |> MapSet.new()

    all_keys = MapSet.union(persisted_keys, pending_keys)

    for key <- all_keys, reduce: %{} do
      acc ->
        case fetch_latest_value(cookie_store, key) do
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

  @doc """
  Merges cookie operations into the pending field of the cookie store.

  Only operations with timestamps higher than existing operations are merged.
  Plain string values in the persisted field are treated as having timestamp 0.

  ## Parameters

    * `cookie_store` - The current cookie store
    * `ops` - A map of cookie operations to merge

  ## Returns

  The updated cookie store with new operations merged into the pending field.
  """
  @spec merge_pending_ops(t, %{String.t() => Cookie.op()}) :: t
  def merge_pending_ops(%CookieStore{} = cookie_store, ops) do
    new_pending =
      for {key, op} <- ops, reduce: cookie_store.pending do
        acc ->
          if should_merge_op?(cookie_store, key, op) do
            Map.put(acc, key, op)
          else
            acc
          end
      end

    %{cookie_store | pending: new_pending}
  end

  # Fetch the latest timestamp for a key based on timestamp precedence
  # Returns {:ok, timestamp} for existing cookies
  # Returns :error for deleted or non-existent cookies
  defp fetch_latest_timestamp(cookie_store, key) do
    persisted_op = Map.get(cookie_store.persisted, key)
    pending_op = Map.get(cookie_store.pending, key)

    ops =
      []
      |> maybe_collect_op(persisted_op)
      |> maybe_collect_op(pending_op)

    # Sort by timestamp (highest first) and get the most recent op
    case Enum.sort_by(ops, &elem(&1, 1), :desc) do
      [] -> :error
      [{:put, timestamp, _value} | _rest] -> {:ok, timestamp}
      [{:delete, _timestamp} | _rest] -> :error
    end
  end

  # Fetch the latest value for a key based on timestamp precedence
  # Returns {:ok, value} for existing cookies (value may be nil)
  # Returns :error for deleted or non-existent cookies
  defp fetch_latest_value(cookie_store, key) do
    persisted_op = Map.get(cookie_store.persisted, key)
    pending_op = Map.get(cookie_store.pending, key)

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

  defp get_op_timestamp({:put, timestamp, _cookie}), do: timestamp
  defp get_op_timestamp({:delete, timestamp}), do: timestamp

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

  # Determines if a new operation should be merged based on timestamp comparison
  defp should_merge_op?(cookie_store, key, op) do
    case fetch_latest_timestamp(cookie_store, key) do
      {:ok, timestamp} ->
        get_op_timestamp(op) > timestamp

      :error ->
        true
    end
  end
end
