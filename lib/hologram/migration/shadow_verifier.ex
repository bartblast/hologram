defmodule Hologram.Migration.ShadowVerifier do
  @moduledoc false

  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Schema
  alias Hologram.Entity.Model
  alias Hologram.Migrator
  alias Hologram.Reflection

  # Fixed application-defined key for pg_advisory_lock - one verification at a time per
  # server, since the scratch database is named after the configured one and two runs
  # would race to create and drop the same name. Session-scoped rather than transactional:
  # creating a database cannot run inside a transaction. Provenance (for uniqueness, not
  # for re-derivation): first 8 bytes of md5("hologram_shadow_verification") as a signed
  # int64.
  @advisory_lock_key 2_569_918_074_951_200_709

  @doc """
  Validates that applying the given migrations from the empty model onto a scratch
  database produces exactly the given model's schema.

  A scratch database named after the configured one (`<database>_shadow`, fitted to the
  identifier limit) is created, claimed for migrations, and the full chain applied from
  empty - the physical proof that the reviewed files build the declared schema, catching
  what the pure fold cannot: rendering and apply-order defects. The scratch database is
  dropped afterwards, pass or fail. Raises with one line per difference when the replayed
  schema does not match.

  Verification opens its own connections, so it starts the driver rather than assuming
  one is running - a mix task loads config without starting applications, and this is
  the only part of generating or checking a migration that reaches a database. An
  advisory lock admits one verification at a time per server: the scratch database is
  named after the configured one, so concurrent runs would otherwise race to create and
  drop the same name.
  """
  @spec verify!(list(%{atom => any}), %{atom => any}) :: :ok
  def verify!(migrations, current_model) do
    {:ok, _apps} = Application.ensure_all_started(:postgrex)

    # Fitted rather than concatenated: PostgreSQL truncates an over-long identifier to 63
    # bytes without saying so, and a configured name already at the limit truncates its own
    # suffix away - so the drop that clears a stale scratch database would name the
    # configured one and take it. Fitting also keeps two long configured names apart, which
    # bare truncation does not.
    shadow_database = Mapper.fit_identifier(Config.connection_opts()[:database] <> "_shadow")

    maintenance_pid = start_connection("postgres")

    # Stopping the connection is what releases the lock, so it is the outermost step - a
    # failure to drop the scratch database must not leave the lock held, or every later run
    # waits on it forever.
    try do
      # Held for the whole lifecycle and released when the connection stops, so a crash
      # frees it too. A waiting run finds the scratch database gone rather than half-built.
      #
      # The wait is unbounded because the run ahead sets its length, and the driver's
      # fifteen second default would end it as an error rather than a wait. This is a direct
      # driver call, so the process-scoped timeout the migration paths set does not reach it.
      Postgrex.query!(maintenance_pid, "SELECT pg_advisory_lock($1)", [@advisory_lock_key],
        timeout: :infinity
      )

      try do
        recreate_shadow!(maintenance_pid, shadow_database)
        run_in_shadow!(shadow_database, migrations, current_model)
      after
        drop_shadow(maintenance_pid, shadow_database)
      end
    after
      GenServer.stop(maintenance_pid)
    end
  end

  # WITH (FORCE) disconnects a backend still tearing down after the applier's
  # connection stopped, rather than failing the drop on it.
  defp drop_shadow(maintenance_pid, shadow_database) do
    quoted_database = Mapper.quote_identifier(shadow_database)

    Postgrex.query!(
      maintenance_pid,
      "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)",
      []
    )
  end

  # A crashed earlier run may have left the scratch database behind - it holds nothing
  # worth keeping, so it is rebuilt from nothing.
  defp recreate_shadow!(maintenance_pid, shadow_database) do
    drop_shadow(maintenance_pid, shadow_database)

    quoted_database = Mapper.quote_identifier(shadow_database)
    Postgrex.query!(maintenance_pid, "CREATE DATABASE #{quoted_database}", [])
  end

  defp replay_and_check!(migrations, current_model) do
    context = run_context()

    {:ok, _status} = Connection.transaction(fn -> Migrator.ensure_managed!(context) end)

    Migrator.apply_pending(migrations, Model.empty(), context)

    expected =
      current_model
      |> Mapper.derive_from_model!()
      |> Schema.from_mapping()

    diff_ops = Schema.diff(Introspection.schema(), expected)

    if diff_ops != [] do
      lines = Enum.map_join(diff_ops, "\n", &"  * #{Migrator.describe_difference(&1)}")

      raise "shadow verification failed - replaying the migration history does not " <>
              "produce the model's schema:\n" <> lines
    end

    :ok
  end

  defp run_context do
    %{
      otp_app: Atom.to_string(Reflection.otp_app()),
      env: Atom.to_string(Hologram.env()),
      hologram_version: to_string(Application.spec(:hologram, :vsn)),
      timestamp: DateTime.utc_now(:microsecond)
    }
  end

  defp run_in_shadow!(shadow_database, migrations, current_model) do
    shadow_pid = start_connection(shadow_database)

    try do
      Connection.with_connection(shadow_pid, fn ->
        # The replay applies the whole chain, so its statements are as long-running as the
        # ones a deploy runs - the driver's default would cut the slow ones short.
        Connection.with_timeout(:infinity, fn ->
          replay_and_check!(migrations, current_model)
        end)
      end)
    after
      GenServer.stop(shadow_pid)
    end
  end

  defp start_connection(database) do
    connection_opts = Config.connection_opts(database: database)
    {:ok, connection_pid} = Postgrex.start_link(connection_opts)

    connection_pid
  end
end
