defmodule Hologram.Compiler.Tracer do
  @moduledoc false

  # Records the bytecode of every module the Elixir compiler compiles in this VM, so that a
  # live-reload compile takes its edited and added modules from here instead of checking every beam
  # of the project (see Hologram.Compiler.patch_module_info_plt!/5). Hologram.Compiler.Cache
  # registers it when the cache starts, before the first scan in the VM, and owns the table, so the
  # records live exactly as long as the kept state they are for: without the cache the next compile
  # is cold and scans everything.

  @table __MODULE__

  @doc """
  Creates the table, owned by the caller, unless it exists, and adds the tracer to the compiler's
  tracers unless it is there. Idempotent.
  """
  @spec register() :: :ok
  def register do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    end

    tracers = Code.get_compiler_option(:tracers)

    if __MODULE__ not in tracers do
      Code.put_compiler_option(:tracers, [__MODULE__ | tracers])
    end

    :ok
  end

  @doc """
  Returns the modules compiled since the last take whose beams in `beam_paths` hold what the
  compiler produced, and forgets their records. The compiler reports a module before it writes its
  beam, and Mix stamps the beam with the time its compile started, so the file's bytes are compared
  with the reported bytecode rather than its mtime with the report's time: a module whose file does
  not hold its bytecode yet keeps its record for the next take. A module with no beam in
  `beam_paths` has nothing to read, so its record is forgotten. A module compiled again after the
  table was read keeps its newer record. The empty set when the table does not exist.
  """
  @spec take(%{module => charlist}) :: MapSet.t(module)
  def take(beam_paths) do
    @table
    |> :ets.tab2list()
    |> Enum.reduce(MapSet.new(), &take_record(&1, &2, beam_paths))
  rescue
    ArgumentError -> MapSet.new()
  end

  @doc """
  Compiler tracer callback: records the bytecode of the module of an `:on_module` event, and
  ignores the rest. Does nothing when the table is gone with the cache, so that no compile fails on
  Hologram's account.
  """
  @spec trace(tuple, Macro.Env.t()) :: :ok
  def trace({:on_module, bytecode, _ignore}, env) do
    :ets.insert(@table, {env.module, bytecode})
    :ok
  rescue
    ArgumentError -> :ok
  end

  def trace(_event, _env), do: :ok

  defp take_record({module, bytecode} = record, taken, beam_paths) do
    case beam_paths do
      %{^module => beam_path} ->
        if File.read(beam_path) == {:ok, bytecode} do
          :ets.delete_object(@table, record)
          MapSet.put(taken, module)
        else
          taken
        end

      _no_beam ->
        :ets.delete_object(@table, record)
        taken
    end
  end
end
