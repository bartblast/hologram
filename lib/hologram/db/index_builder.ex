defmodule Hologram.DB.IndexBuilder do
  @moduledoc false

  # Builds the index plan's indexes on a database migrations manage, after the node starts serving
  # (see Hologram.DB.IndexPlan). A plan index carries no data and changes no answer, only how fast
  # one comes, so a boot doesn't wait for it: on a big table a build takes minutes, and every node
  # of a deploy would wait behind the first one's. The boot builds what the model derives - primary
  # keys and unique indexes, which writes rely on - and this builds the rest.
  #
  # One step at a time, each under the migration lock, which it takes by polling and lets go of
  # once the step is done (see Hologram.Migrator.with_migration_lock/1): a concurrent build next to
  # another node's schema change deadlocks, and the lock is what keeps them apart. What to do next
  # is read again under the lock each time, so builders on several nodes share the work and a step
  # another node did is not done twice. The steps, in order:
  #
  #   1. drop an invalid plan index - a build that died partway, which serves no query and costs
  #      every write - CONCURRENTLY, so the next steps build it again
  #   2. rename the plan indexes standing under another name with the plan's definition - what a
  #      migration renaming a relationship or an entity leaves - in one transaction
  #   3. drop a plan index the plan no longer names, or names with another definition, CONCURRENTLY,
  #      so a stale one costs no write and frees its name for the one the plan wants
  #   4. build a missing one CONCURRENTLY
  #
  # A node whose chain lacks a migration the database applied runs older code than the database, so
  # its plan would drop the indexes a newer release needs and rename theirs back: it only does 1
  # and 4. Old and new nodes serving one database at once is #1627.
  #
  # Between two steps it waits a little longer than a booting node polls for the lock, and it polls
  # for the lock five times slower than one, so a boot that needs the lock - one applying a
  # migration - most likely waits for one step, not for every build left: a builder waiting beside
  # it can still win a pause, more often the more of them wait.
  #
  # A step it took that comes up again means another node undid it - most likely a node of another
  # release, whose plan differs. Two such builders would undo each other back to back for as long
  # as both run, each with a full-table build, so the one that sees it backs off - a longer wait each
  # time - and converges again from a fresh read, which ends once the other release's nodes are
  # gone. Old and new releases serving one database at once is #1627.
  #
  # Started last in the database unit, outside dev and test (see Hologram.DB.Supervisor), as a
  # transient child that stops once nothing is left to do - and is started again when an earlier
  # child's restart takes it down mid-way, which a temporary one never would be. A step that fails -
  # a lost connection, a build PostgreSQL refuses - is logged and tried again after a while, from a
  # fresh read. It traps exits, so a session that dies (see
  # Hologram.Migrator.with_migration_connection/1) is one of those failures rather than the end of
  # the builder - and is killed outright when the unit stops, since a process trapping exits that
  # reads no messages would hold the stop up. Its session closes with it, which releases the lock
  # once the step running ends.

  use Task, restart: :transient, shutdown: :brutal_kill

  require Logger

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.Migration.Loader
  alias Hologram.Migrator

  @retry_interval_ms 30_000

  # Longer than Hologram.Migrator's @migration_lock_poll_interval_ms, so a booting node polling for
  # the lock gets a try in between.
  @step_pause_ms 1_500

  # Five times Hologram.Migrator's @migration_lock_poll_interval_ms.
  @lock_poll_interval_ms 5_000

  # The longest a builder backs off for after another node undid its step.
  @max_backoff_ms 600_000

  @doc """
  Starts the builder, which converges the plan's indexes (see `run/1`) and stops.
  """
  @spec start_link(keyword) :: {:ok, pid}
  def start_link(opts) do
    Task.start_link(__MODULE__, :run, [opts])
  end

  @doc """
  Converges the given index plan's indexes on the database currently connected (see `converge/3`),
  on a session of its own with no statement timeout, and returns :ok once nothing is left to do.
  A run that raises or exits - loading the plan included - is logged as a warning and tried again
  after the given interval.

  Options: `:plan` (the app's, `Hologram.DB.IndexPlan.plan/1` over `Hologram.DB.mapping/0`, when
  absent), `:migrations` (the app's when absent), `:retry_interval_ms` and `:step_pause_ms` (see
  `converge/3`).
  """
  @spec run(keyword) :: :ok
  def run(opts \\ []) do
    Process.flag(:trap_exit, true)

    attempt(opts, Keyword.get(opts, :retry_interval_ms, @retry_interval_ms), 0)
  end

  @doc """
  Converges the given index plan's indexes on the current session, one step at a time under the
  migration lock, and returns :ok once nothing is left to do, or `{:undone, step}` once a step it
  took comes up again - another node undid it. The given migrations are the node's chain, which
  says whether the database applied a migration the node doesn't know.

  Options: `:step_pause_ms`, how long it waits between two steps, 1.5 s when absent.
  """
  @spec converge(%{String.t() => %{String.t() => map}}, list(%{atom => any}), keyword) ::
          :ok | {:undone, tuple}
  def converge(plan, migrations, opts \\ []) do
    known_versions = MapSet.new(migrations, & &1.version)

    unknown_versions =
      Enum.reject(Migrator.applied_versions(), &MapSet.member?(known_versions, &1))

    if unknown_versions != [] do
      Logger.warning(
        "Hologram: the database has applied migrations this release doesn't hold " <>
          "(#{Enum.join(Enum.sort(unknown_versions), ", ")}), so it leaves indexes it doesn't " <>
          "plan in place"
      )
    end

    step_pause_ms = Keyword.get(opts, :step_pause_ms, @step_pause_ms)

    converge_steps(plan, known_versions, step_pause_ms, [])
  end

  defp attempt(opts, retry_interval_ms, undone_count) do
    outcome =
      try do
        plan = Keyword.get_lazy(opts, :plan, fn -> IndexPlan.plan(DB.mapping()) end)
        migrations = Keyword.get_lazy(opts, :migrations, &Loader.list!/0)

        Migrator.with_migration_connection(fn ->
          Connection.with_timeout(:infinity, fn -> converge(plan, migrations, opts) end)
        end)
      rescue
        error -> {:failed, Exception.message(error)}
      catch
        :exit, reason -> {:failed, Exception.format_exit(reason)}
      end

    # The exits of the sessions it opened, which it traps.
    flush_exits()

    case outcome do
      :ok ->
        :ok

      {:failed, cause} ->
        Logger.warning(
          "Hologram: building the indexes the queries need failed, and is tried again in " <>
            "#{retry_interval_ms} ms: " <> cause
        )

        Process.sleep(retry_interval_ms)

        attempt(opts, retry_interval_ms, undone_count)

      {:undone, step} ->
        backoff_ms = min(retry_interval_ms * Integer.pow(2, undone_count), @max_backoff_ms)

        Logger.warning(
          "Hologram: #{describe_step(step)} came up again - another node, likely of another " <>
            "release, undid it - so building the indexes the queries need is tried again in " <>
            "#{backoff_ms} ms"
        )

        Process.sleep(backoff_ms)

        attempt(opts, retry_interval_ms, undone_count + 1)
    end
  end

  defp converge_steps(plan, known_versions, step_pause_ms, taken_steps) do
    outcome =
      Migrator.with_migration_lock(
        fn ->
          chain_known? =
            Enum.all?(Migrator.applied_versions(), &MapSet.member?(known_versions, &1))

          case next_step(plan, chain_known?) do
            :done -> :done
            step -> take_step(step, taken_steps)
          end
        end,
        @lock_poll_interval_ms
      )

    case outcome do
      :done ->
        :ok

      {:undone, _step} = undone ->
        undone

      {:taken, step} ->
        Process.sleep(step_pause_ms)

        converge_steps(plan, known_versions, step_pause_ms, [step | taken_steps])
    end
  end

  defp describe_step({:create, op}), do: ~s(building index "#{op.index}")

  defp describe_step({:rename, renames}) do
    Enum.map_join(renames, ", ", &~s(renaming index "#{&1.from}" to "#{&1.to}"))
  end

  defp describe_step({_drop, index}), do: ~s(dropping index "#{index}")

  defp flush_exits do
    receive do
      {:EXIT, _pid, _reason} -> flush_exits()
    after
      0 -> :ok
    end
  end

  defp next_step(plan, chain_known?) do
    actual = Introspection.schema()
    owned_names = IndexPlan.owned_index_names(actual)

    with nil <- invalid_index(owned_names),
         nil <- if(chain_known?, do: renames(actual, plan, owned_names)),
         nil <- if(chain_known?, do: unused_index(actual, plan, owned_names)),
         nil <- missing_index(actual, plan) do
      :done
    end
  end

  defp run_step({:drop_invalid, index}) do
    drop_concurrently(index)

    Logger.info(~s(Hologram: dropped index "#{index}", which a build left invalid))
  end

  defp run_step({:rename, renames}) do
    indexed_renames = Enum.with_index(renames)

    {:ok, _result} =
      Connection.transaction(fn -> rename_through_temporary_names(indexed_renames) end)

    Enum.each(renames, fn rename ->
      Logger.info(
        ~s(Hologram: renamed index "#{rename.from}" to "#{rename.to}" to follow the current naming rule)
      )
    end)
  end

  defp run_step({:drop_unused, index}) do
    drop_concurrently(index)

    Logger.info(~s(Hologram: dropped index "#{index}", which no query and no lookup needs))
  end

  defp run_step({:create, op}) do
    op
    |> Map.put(:concurrently, true)
    |> DDL.statements()
    |> Enum.each(&({:ok, _result} = Connection.query(&1)))

    Logger.info(~s(Hologram: built index "#{op.index}", which the queries need))
  end

  defp take_step(step, taken_steps) do
    if step in taken_steps do
      {:undone, step}
    else
      run_step(step)

      {:taken, step}
    end
  end

  defp drop_concurrently(index) do
    [statement] = DDL.statements(%{op: :drop_index, index: index, concurrently: true})

    {:ok, _result} = Connection.query(statement)
  end

  # An invalid index the plan owns, by its shape: unique ones are the migrator's to rebuild, and
  # one of another shape is the drift check's to report.
  defp invalid_index(owned_names) do
    statement = DDL.invalid_indexes_statement(false)
    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.find_value(rows, fn [index] ->
      if MapSet.member?(owned_names, index), do: {:drop_invalid, index}
    end)
  end

  # The first index the plan names that the database lacks, on a table and columns it has, under a
  # name nothing holds - a name an index outside the plan holds is the drift check's to report.
  defp missing_index(actual, plan) do
    held_names = held_index_names(actual)

    missing =
      for {table, indexes} <- Enum.sort(plan),
          table_definition = actual.tables[table],
          table_definition != nil,
          {name, definition} <- Enum.sort(indexes),
          not MapSet.member?(held_names, name),
          Enum.all?(definition.columns, &Map.has_key?(table_definition.columns, &1)),
          do: {:create, Map.merge(definition, %{op: :create_index, table: table, index: name})}

    List.first(missing)
  end

  defp unused_index(actual, plan, owned_names) do
    unused =
      for {table, definition} <- Enum.sort(actual.tables),
          {name, index} <- Enum.sort(definition.indexes),
          MapSet.member?(owned_names, name),
          get_in(plan, [table, name]) != plain_definition(index),
          do: {:drop_unused, name}

    List.first(unused)
  end

  defp held_index_names(actual) do
    for {_table, definition} <- actual.tables,
        name <- Map.keys(definition.indexes),
        into: MapSet.new(),
        do: name
  end

  # A plan index standing under a name the plan doesn't give its definition - the name a renamed
  # relationship or entity left it under - pairs with the plan's index of that definition on the
  # same table, one to one, and is renamed. Renames run in one transaction, each index first to a
  # temporary name and then to its own, so two indexes whose names swap are renamed rather than
  # rebuilt: ALTER INDEX ... RENAME takes no long lock, and a node dying halfway would otherwise
  # leave names to untangle. A target an index outside the plan holds is left alone, for the drift
  # check to report, and so is one a plan index holds that no rename moves away - that index is
  # then dropped as unused and the target built.
  defp renames(actual, plan, owned_names) do
    held_names = held_index_names(actual)

    renames =
      plan
      |> Enum.sort()
      |> Enum.flat_map(fn {table, indexes} ->
        actual_indexes = Map.get(actual.tables, table, %{indexes: %{}}).indexes

        strays =
          for {name, index} <- Enum.sort(actual_indexes),
              MapSet.member?(owned_names, name),
              Map.get(indexes, name) != plain_definition(index),
              do: {name, plain_definition(index)}

        wanted =
          for {name, definition} <- Enum.sort(indexes),
              plain_definition(Map.get(actual_indexes, name)) != definition,
              not MapSet.member?(held_names, name) or MapSet.member?(owned_names, name),
              do: {name, definition}

        wanted_names = MapSet.new(wanted, fn {name, _definition} -> name end)

        # A stray standing in a name another wanted index needs goes first among its equals:
        # renamed away, it frees that name too, where pairing another would leave it to be
        # dropped and rebuilt.
        strays
        |> Enum.sort_by(fn {name, _definition} ->
          {not MapSet.member?(wanted_names, name), name}
        end)
        |> pair_renames(wanted, table)
      end)
      |> free_targets(held_names)

    if renames != [], do: {:rename, renames}
  end

  # A rename lands only where nothing will stand: its target free, or held by an index this run
  # renames away. Leaving one out can take a target back from another, so it runs to a fixed point.
  defp free_targets(renames, held_names) do
    froms = MapSet.new(renames, & &1.from)

    landing =
      Enum.filter(
        renames,
        &(not MapSet.member?(held_names, &1.to) or MapSet.member?(froms, &1.to))
      )

    if length(landing) == length(renames), do: renames, else: free_targets(landing, held_names)
  end

  # One to one by definition, in a fixed order on both sides, so the plan's renames never depend
  # on the order the catalog lists indexes in.
  defp pair_renames(strays, wanted, table) do
    {renames, _left} =
      Enum.reduce(wanted, {[], strays}, fn {to, definition}, {acc, left} ->
        case List.keyfind(left, definition, 1) do
          {from, _definition} = stray ->
            {[%{op: :rename_index, table: table, from: from, to: to} | acc],
             List.delete(left, stray)}

          nil ->
            {acc, left}
        end
      end)

    Enum.reverse(renames)
  end

  defp plain_definition(nil), do: nil

  defp plain_definition(index), do: Map.take(index, [:columns, :nulls_distinct, :unique])

  defp rename_index(from, to) do
    statement =
      "ALTER INDEX #{Mapper.quote_identifier(Mapper.data_schema())}.#{Mapper.quote_identifier(from)} " <>
        "RENAME TO #{Mapper.quote_identifier(to)}"

    {:ok, _result} = Connection.query(statement)
  end

  defp rename_through_temporary_names(indexed_renames) do
    Enum.each(indexed_renames, fn {rename, index} ->
      rename_index(rename.from, temporary_index_name(index))
    end)

    Enum.each(indexed_renames, fn {rename, index} ->
      rename_index(temporary_index_name(index), rename.to)
    end)
  end

  # Outside every name the derived scheme gives - no derived name starts with `$` - and short.
  defp temporary_index_name(index), do: "$plan_rename_#{index}"
end
