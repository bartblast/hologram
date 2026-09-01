defmodule Hologram.Migration.ShadowVerifierTest do
  # async: false - the scratch database is a per-suite singleton (the configured name
  # + "_shadow"), so concurrent verifications would tread on each other.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Migration.ShadowVerifier

  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.Entity.Model

  # A configured name filling the PostgreSQL identifier limit exactly - concatenating the
  # scratch suffix onto it produces 70 bytes, whose first 63 are the name itself.
  @limit_database String.pad_trailing("hologram_database_named_at_the_identifier_limit_", 63, "x")

  @ops [
    %{op: :create_entity, entity: MyApp.Task, line: 3},
    %{op: :add_attribute, entity: MyApp.Task, name: :title, type: :string, opts: [], line: 4}
  ]

  @migrations [%{version: "20260813091522", path: "20260813091522.exs", ops: @ops}]

  defp mismatch_message do
    normalize_newlines("""
    shadow verification failed - replaying the migration history does not produce the model's schema:
      * column "done" on table "my_app_task" declared by the model is missing\
    """)
  end

  defp mismatched_model do
    done_op = %{
      op: :add_attribute,
      entity: MyApp.Task,
      name: :done,
      type: :boolean,
      opts: [default: false],
      line: 5
    }

    Model.empty()
    |> Model.fold(@ops)
    |> Model.fold([done_op])
  end

  defp database_exists?(name) do
    statement = "SELECT 1 FROM pg_database WHERE datname = $1"

    {:ok, %{rows: rows}} = Connection.query(statement, [name])

    rows != []
  end

  defp shadow_database_exists? do
    database_opts =
      :hologram
      |> Application.get_env(:database, [])
      |> Config.resolve!(:test)

    database_exists?(Mapper.fit_identifier(database_opts[:database] <> "_shadow"))
  end

  # Opened outside the pool and outside the sandbox: CREATE and DROP DATABASE cannot run
  # inside a transaction, which is what every pooled connection here is holding.
  defp with_maintenance(fun) do
    maintenance_opts = Config.connection_opts(database: "postgres")
    {:ok, pid} = Postgrex.start_link(maintenance_opts)

    try do
      fun.(pid)
    after
      GenServer.stop(pid)
    end
  end

  describe "verify!/2" do
    test "passes a chain producing the model's schema" do
      model = Model.fold(Model.empty(), @ops)

      assert verify!(@migrations, model) == :ok
    end

    test "passes a chain that designates a user entity before any role" do
      ops = [
        %{op: :create_entity, entity: MyApp.User, line: 3},
        %{op: :designate_user_entity, entity: MyApp.User, line: 4}
      ]

      migrations = [%{version: "20260813091522", path: "20260813091522.exs", ops: ops}]
      model = Model.fold(Model.empty(), ops)

      assert verify!(migrations, model) == :ok
    end

    test "drops the scratch database after a pass" do
      model = Model.fold(Model.empty(), @ops)
      verify!(@migrations, model)

      refute shadow_database_exists?()
    end

    test "serializes concurrent verifications" do
      model = Model.fold(Model.empty(), @ops)

      results =
        1..3
        |> Enum.map(fn _i -> Task.async(fn -> verify!(@migrations, model) end) end)
        |> Task.await_many(120_000)

      # Without the lock they race to create and drop one scratch database named after
      # the configured one, and every run fails rather than one winning.
      assert results == [:ok, :ok, :ok]
    end

    test "leaves a configured database named at the identifier limit alone" do
      with_maintenance(fn pid ->
        Postgrex.query!(pid, ~s|DROP DATABASE IF EXISTS "#{@limit_database}" WITH (FORCE)|, [])
        Postgrex.query!(pid, ~s|CREATE DATABASE "#{@limit_database}"|, [])
      end)

      on_exit(fn ->
        with_maintenance(fn pid ->
          Postgrex.query!(pid, ~s|DROP DATABASE IF EXISTS "#{@limit_database}" WITH (FORCE)|, [])
        end)
      end)

      original_config = Application.get_env(:hologram, :database, [])
      on_exit(fn -> Application.put_env(:hologram, :database, original_config) end)

      Application.put_env(
        :hologram,
        :database,
        Keyword.put(original_config, :database, @limit_database)
      )

      # The scratch name is fitted, so it stays distinct - concatenated, PostgreSQL would
      # truncate it back onto the configured name and the run would drop the real database
      # before creating anything.
      verify!(@migrations, Model.fold(Model.empty(), @ops))

      assert database_exists?(@limit_database)
    end

    test "raises naming the target when the server cannot be reached" do
      original_config = Application.get_env(:hologram, :database, [])
      on_exit(fn -> Application.put_env(:hologram, :database, original_config) end)

      Application.put_env(:hologram, :database, Keyword.put(original_config, :port, 59_999))

      expected_msg =
        "shadow verification could not reach the Postgres server at localhost:59999 as " <>
          ~s(user "postgres" - it opens its own connection there to build the scratch ) <>
          "database. The connection error logged above says which of these it is: no " <>
          ~s(server running, refused credentials, or a missing "postgres" maintenance ) <>
          "database."

      assert_error RuntimeError, expected_msg, fn ->
        verify!(@migrations, Model.fold(Model.empty(), @ops))
      end
    end

    test "raises when the replay does not produce the model's schema" do
      assert_error RuntimeError, mismatch_message(), fn ->
        verify!(@migrations, mismatched_model())
      end
    end

    test "drops the scratch database after a failure" do
      assert_error RuntimeError, mismatch_message(), fn ->
        verify!(@migrations, mismatched_model())
      end

      refute shadow_database_exists?()
    end
  end
end
