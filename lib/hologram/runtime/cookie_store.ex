defmodule Hologram.Runtime.CookieStore do
  @moduledoc false

  alias Hologram.Runtime.Cookie
  alias Hologram.Runtime.CookieStore
  alias Hologram.Runtime.PlugConnUtils

  defstruct persisted: %{}, pending: %{}

  @type t :: %__MODULE__{
          persisted: %{String.t() => op()},
          pending: %{String.t() => op()}
        }

  # "nop" = no operation - used for pre-existing cookies fetched from the initial Plug.Conn struct
  # The second element is the operation timestamp
  @type op :: {:delete, pos_integer} | {:nop, 0, any} | {:put, pos_integer, Cookie.t()}

  @doc """
  Returns a map of effective cookies from the cookie store.

  Values from pending cookie operations with higher timestamps take precedence over
  already persisted cookie operations with smaller timestamps. Deleted cookies are excluded.

  ## Examples

      iex> store = %CookieStore{
      ...>   persisted: %{
      ...>     "key_1" => {:nop, 0, "value_1"},
      ...>.    "key_2" => {:put, 100, %Cookie{value: "old_value"}}
      ...>.  },
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
        case fetch_effective_value(cookie_store, key) do
          {:ok, value} -> Map.put(acc, key, value)
          :error -> acc
        end
    end
  end

  @doc """
  Creates a new cookie store from a Plug.Conn struct.

  Extracts cookies from the given connection and stores them as persisted ops
  in the returned cookie store. The pending ops map will be empty.
  The Hologram session cookie (hologram_session) is excluded.

  ## Parameters

    * `conn` - A Plug.Conn struct containing cookies to extract

  ## Examples

      iex> conn = %Plug.Conn{req_headers: [{"cookie", "user_id=abc123; theme=dark"}]}
      iex> store = CookieStore.from(conn)
      iex> store.persisted
      %{"user_id" => {:nop, 0, "abc123"}, "theme" => {:nop, 0, "dark"}}
      iex> store.pending
      %{}
  """
  @spec from(Plug.Conn.t()) :: t
  def from(%Plug.Conn{} = conn) do
    persisted =
      conn
      |> PlugConnUtils.extract_cookies()
      |> Enum.map(fn {key, value} -> {key, {:nop, 0, value}} end)
      |> Enum.into(%{})

    %__MODULE__{
      persisted: persisted
    }
  end

  @doc """
  Returns true if the cookie store has any pending operations, false otherwise.
  """
  @spec has_pending_ops?(t) :: boolean
  def has_pending_ops?(cookie_store) do
    Enum.any?(cookie_store.pending)
  end

  @doc """
  Merges cookie operations into the cookie store's pending operations.

  Only operations with timestamps higher than existing operations are merged.

  ## Parameters

    * `cookie_store` - The current cookie store
    * `ops` - A map of cookie operations to merge

  ## Returns

  The updated cookie store with new operations merged into the pending field.
  """
  @spec merge_pending_ops(t, %{String.t() => op()}) :: t
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

  defp effective_op(op_1, op_2) do
    case {op_1, op_2} do
      {nil, nil} ->
        :error

      {op_1, nil} ->
        op_1

      {nil, op_2} ->
        op_2

      {op_1, op_2} ->
        if elem(op_2, 1) > elem(op_1, 1) do
          op_2
        else
          op_1
        end
    end
  end

  # Fetch the effective timestamp for a key based on timestamp precedence
  # Returns {:ok, timestamp} for existing or deleted cookies
  # Returns :error for non-existent cookies
  defp fetch_effective_timestamp(cookie_store, key) do
    persisted_op = Map.get(cookie_store.persisted, key)
    pending_op = Map.get(cookie_store.pending, key)

    case effective_op(persisted_op, pending_op) do
      {:nop, 0, _value} ->
        {:ok, 0}

      {:put, timestamp, _cookie} ->
        {:ok, timestamp}

      {:delete, timestamp} ->
        {:ok, timestamp}

      :error ->
        :error
    end
  end

  # Fetch the effective value for a key based on timestamp precedence
  # Returns {:ok, value} for existing cookies
  # Returns :error for deleted or non-existent cookies
  defp fetch_effective_value(cookie_store, key) do
    persisted_op = Map.get(cookie_store.persisted, key)
    pending_op = Map.get(cookie_store.pending, key)

    case effective_op(persisted_op, pending_op) do
      {:nop, 0, value} ->
        {:ok, value}

      {:put, _timestamp, %Cookie{value: value}} ->
        {:ok, value}

      {:delete, _timestamp} ->
        :error

      :error ->
        :error
    end
  end

  # Determines if a new operation should be merged based on timestamp comparison
  defp should_merge_op?(cookie_store, key, op) do
    case fetch_effective_timestamp(cookie_store, key) do
      {:ok, timestamp} ->
        elem(op, 1) > timestamp

      :error ->
        true
    end
  end
end
