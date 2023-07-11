defmodule Hologram.Commons.PersistentLookupTable do
  use GenServer

  alias Hologram.Commons.PersistentLookupTable
  alias Hologram.Commons.SerializationUtils

  defstruct pid: nil, name: nil
  @type t :: %PersistentLookupTable{pid: pid, name: atom}

  @doc """
  Returns the value stored in the underlying ETS table under the given key.

  ## Examples

      iex> get(%PersistentLookupTable{name: :my_plt}, :my_key)
      :my_value

  """
  @spec get(PersistentLookupTable.t(), atom) :: {:ok, term} | :error
  def get(plt, key) do
    case :ets.lookup(plt.name, key) do
      [{^key, value}] ->
        {:ok, value}

      _fallback ->
        :error
    end
  end

  @doc """
  Returns all items stored in the underlying ETS table.

  ## Examples

      iex> get_all(%PersistentLookupTable{name :my_plt})
      %{key_1: :value_1, key_2: :value_2}
  """
  @spec get_all(PersistentLookupTable.t()) :: %{atom => term}
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

      iex> put(%PersistentLookupTable{name: :my_plt}, :my_key, :my_value)
      true

      iex> put(:my_plt, :my_key, :my_value)
      true

  """
  @spec put(PersistentLookupTable.t(), atom, term) :: true

  def put(%PersistentLookupTable{name: name}, key, value) do
    put(name, key, value)
  end

  def put(name, key, value) do
    :ets.insert(name, {key, value})
  end

  @doc """
  Tells whether the underlying GenServer process is alive.

  ## Examples

      iex> running?(:my_plt)
      true
  """
  @spec running?(atom) :: boolean
  def running?(name) do
    pid = Process.whereis(name)
    if pid, do: Process.alive?(pid), else: false
  end

  @doc """
  Starts the underlying GenServer process.

  ## Examples

      iex> start(name: :my_plt, dump_path: "/my_dump_path")
      %PersistentLookupTable{pid: #PID<0.273.0>, name: :my_plt}
  """
  @spec start(keyword) :: PersistentLookupTable.t()
  def start(opts) do
    {:ok, pid} = GenServer.start_link(PersistentLookupTable, opts, name: opts[:name])
    %PersistentLookupTable{pid: pid, name: opts[:name]}
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
