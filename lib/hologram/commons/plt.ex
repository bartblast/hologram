defmodule Hologram.Commons.PLT do
  @moduledoc """
  Provides a persistent lookup table (PLT) implemented using ETS (Erlang Term Storage) and GenServer.
  It allows you to store key-value pairs in memory and perform various operations on the data.
  """

  use GenServer

  alias Hologram.Commons.PLT
  alias Hologram.Commons.SerializationUtils

  defstruct pid: nil, name: nil, dump_path: nil
  @type t :: %PLT{pid: pid, name: atom, dump_path: String.t() | nil}

  @doc """
  Deletes a key-value pair from the give persistent lookup table.

  ## Examples

      iex> my_plt = %PLT{pid: #PID<0.273.0>, name: :my_plt}
      iex> delete(my_plt, :my_key)
      %PLT{pid: #PID<0.273.0>, name: :my_plt}
  """
  @spec delete(PLT.t(), atom) :: PLT.t()
  def delete(plt, key) do
    :ets.delete(plt.name, key)
    plt
  end

  @doc """
  Serializes the contents of the given PLT's ETS table and writes them to a file.

  ## Examples

      iex> my_plt = %PLT{pid: #PID<0.273.0>, name: :my_plt, dump_path: "/my_dump_path"}
      iex> dump(my_plt)
      :ok
  """
  @spec dump(PLT.t()) :: :ok
  def dump(%PLT{dump_path: dump_path} = plt) do
    data =
      plt
      |> get_all()
      |> SerializationUtils.serialize()

    File.write!(dump_path, data)
  end

  @doc """
  Returns the value stored in the underlying ETS table under the given key.
  If the key doesn't exist the :error :atom is returned.

  ## Examples

      iex> get(%PLT{name: :my_plt}, :my_key)
      :my_value
  """
  @spec get(PLT.t(), atom) :: {:ok, term} | :error
  def get(plt, key) do
    case :ets.lookup(plt.name, key) do
      [{^key, value}] ->
        {:ok, value}

      _fallback ->
        :error
    end
  end

  @doc """
  Returns the value stored in the underlying ETS table under the given key.
  If the key doesn't exist a KeyError is raised.

  ## Examples

      iex> get!(%PLT{name: :my_plt}, :my_key)
      :my_value

      iex> get!(%PLT{name: :my_plt}, :invalid_key)
      ** (KeyError) key :invalid_key not found in the PLT
  """
  @spec get!(PLT.t(), atom) :: term
  def get!(plt, key) do
    case get(plt, key) do
      {:ok, value} -> value
      _fallback -> raise KeyError, message: "key #{inspect(key)} not found in the PLT"
    end
  end

  @doc """
  Returns all items stored in the underlying ETS table.

  ## Examples

      iex> get_all(%PLT{name :my_plt})
      %{key_1: :value_1, key_2: :value_2}
  """
  @spec get_all(PLT.t()) :: %{atom => term}
  def get_all(plt) do
    plt.name
    |> :ets.tab2list()
    |> Enum.into(%{})
  end

  @doc """
  Creates the underlying ETS table if it doesn't exist yet,
  truncates it, and populates it from the dump (if the dump exists).

  ## Examples

      iex> init(name: :my_plt, dump_path: "/my_dump_path")
      {:ok, nil}
  """
  @impl GenServer
  @spec init(keyword) :: {:ok, nil}
  def init(opts) do
    maybe_create_table(opts[:name])
    reload_table(opts)
    {:ok, nil}
  end

  @doc """
  Puts multiple items into the underlying ETS table.

  ## Examples

      iex> put(:my_plt, [key_1: :value_1, key_2: :value_2])
      true
  """
  @spec put(atom, keyword) :: true
  def put(name, items) do
    :ets.insert(name, items)
  end

  @doc """
  Puts the given item into the underlying ETS table.

  ## Examples

      iex> my_plt = %PLT{pid: #PID<0.273.0>, name: :my_plt}
      iex> put(my_plt, :my_key, :my_value)
      %PLT{pid: #PID<0.273.0>, name: :my_plt}

      iex> put(:my_plt, :my_key, :my_value)
      true
  """
  @spec put(PLT.t() | atom, atom, term) :: PLT.t() | true

  def put(%PLT{name: name} = plt, key, value) do
    put(name, key, value)
    plt
  end

  def put(name, key, value) do
    :ets.insert(name, {key, value})
  end

  @doc """
  Starts the underlying GenServer process.

  ## Examples

      iex> start(name: :my_plt, dump_path: "/my_dump_path")
      %PLT{pid: #PID<0.273.0>, name: :my_plt, dump_path: "/my_dump_path"}
  """
  @spec start(keyword) :: PLT.t()
  def start(opts) do
    {:ok, pid} = GenServer.start_link(PLT, opts, name: opts[:name])
    %PLT{pid: pid, name: opts[:name], dump_path: opts[:dump_path]}
  end

  @doc """
  Tells whether the underlying ETS table exists.

  ## Examples

      iex> table_exists?(:my_plt)
      true
  """
  @spec table_exists?(atom) :: boolean
  def table_exists?(name) do
    :ets.info(name) != :undefined
  end

  defp create_table(name) do
    :ets.new(name, [:public, :named_table])
  end

  defp maybe_create_table(name) do
    if !table_exists?(name), do: create_table(name)
  end

  defp populate_table(opts) do
    items =
      opts[:dump_path]
      |> File.read!()
      |> SerializationUtils.deserialize()
      |> Map.to_list()

    put(opts[:name], items)
  end

  defp reload_table(opts) do
    truncate_table(opts[:name])

    if opts[:dump_path] && File.exists?(opts[:dump_path]) do
      populate_table_fun = opts[:populate_table_fun] || (&populate_table/1)
      populate_table_fun.(opts)
    end
  end

  defp truncate_table(name) do
    :ets.delete_all_objects(name)
  end
end
