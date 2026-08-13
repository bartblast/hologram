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

  @doc """
  Validates that applying the given migrations from the empty model onto a scratch
  database produces exactly the given model's schema.

  A scratch database named after the configured one (`<database>_shadow`) is created,
  claimed for migrations, and the full chain applied from empty - the physical proof
  that the reviewed files build the declared schema, catching what the pure fold
  cannot: rendering and apply-order defects. The scratch database is dropped
  afterwards, pass or fail. Raises with one line per difference when the replayed
  schema does not match.

  Verification opens its own connections, so it starts the driver rather than assuming
  one is running - a mix task loads config without starting applications, and this is
  the only part of generating or checking a migration that reaches a database.
  """
  @spec verify!(list(%{atom => any}), %{atom => map}) :: :ok
  def verify!(migrations, current_model) do
    {:ok, _apps} = Application.ensure_all_started(:postgrex)

    shadow_database = Config.connection_opts()[:database] <> "_shadow"
    maintenance_pid = start_connection("postgres")

    try do
      recreate_shadow!(maintenance_pid, shadow_database)
      run_in_shadow!(shadow_database, migrations, current_model)
    after
      drop_shadow(maintenance_pid, shadow_database)
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
        replay_and_check!(migrations, current_model)
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
