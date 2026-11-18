defmodule Hologram.DBTest do
  # async: false - the boot-mechanism tests flip the HOLOGRAM_ENV env var, which is global.
  use Hologram.Test.DatabaseCase, async: false

  import ExUnit.CaptureLog
  import Hologram.DB
  import Hologram.Query, only: [decrement: 3, put_attribute: 3]
  import Hologram.Test, only: [as_user: 2]

  alias Hologram.AccessDeniedError
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Schema
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.MisuseError
  alias Hologram.Query
  alias Hologram.Reflection
  alias Hologram.SQLError
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module53
  alias Hologram.Test.Fixtures.Entity.Module54
  alias Hologram.Test.Fixtures.Job.Module1, as: JobModule1
  alias Hologram.Test.TCPProxy
  alias Hologram.WriteError

  @stale_model_msg "the code changed since the last compile that validated the data model - fix the compile error, if there is one, and save again"

  # A server that answers every connection the way PostgreSQL does while it starts up: a FATAL
  # 57P03 in place of the authentication request. Returns its port.
  defp start_starting_up_server do
    {:ok, listen_socket} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen_socket)

    fields =
      [{?S, "FATAL"}, {?V, "FATAL"}, {?C, "57P03"}, {?M, "the database system is starting up"}]
      |> Enum.map(fn {type, value} -> <<type, value::binary, 0>> end)
      |> IO.iodata_to_binary()

    error_response = <<?E, byte_size(fields) + 5::32, fields::binary, 0>>

    spawn_link(fn -> answer_starting_up(listen_socket, error_response) end)

    port
  end

  # A connection that goes away before it is answered - its caller killed mid-handshake - is
  # closed and the next one answered.
  defp answer_starting_up(listen_socket, error_response) do
    {:ok, socket} = :gen_tcp.accept(listen_socket)

    with {:ok, _startup_packet} <- :gen_tcp.recv(socket, 0) do
      :gen_tcp.send(socket, error_response)
    end

    :gen_tcp.close(socket)

    answer_starting_up(listen_socket, error_response)
  end

  # A pool behind a proxy that refuses connections until the test opens it, giving up on a checkout
  # and reconnecting within milliseconds rather than seconds. Each try to connect logs, so a test
  # starts it inside its log capture and stops it there with stop_unreachable_pool/0.
  defp start_unreachable_pool(proxy \\ start_supervised!(TCPProxy)) do
    port = TCPProxy.port(proxy)

    opts =
      Config.connection_opts(
        backoff_max: 50,
        backoff_min: 10,
        pool_size: 1,
        port: port,
        queue_interval: 20,
        queue_target: 10
      )

    start_supervised!(Supervisor.child_spec({Postgrex, opts}, id: :unreachable_pool))
  end

  defp stop_unreachable_pool, do: stop_supervised!(:unreachable_pool)

  # Stops a process waiting for the database, and returns once the probe connection it may have
  # been opening is gone too. The probe traps exits and finishes its connect before it goes, so it
  # would otherwise log after the test's capture ended. Suspended first, so it opens no other.
  defp stop_waiter(waiter) do
    :erlang.suspend_process(waiter)
    {:links, links} = Process.info(waiter, :links)

    refs = for pid <- [waiter | Enum.filter(links, &is_pid/1)], do: {pid, Process.monitor(pid)}

    Process.exit(waiter, :kill)

    for {pid, ref} <- refs do
      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      end
    end
  end

  # The boot steps wait before they touch the database: each is left waiting on a pool that
  # cannot reach it, and stopped there.
  defp assert_waits_for_database(boot_step) do
    run_boot_step = fn -> apply(Hologram.DB, boot_step, []) end

    log =
      capture_log(fn ->
        pool = start_unreachable_pool()

        {pid, monitor_ref} =
          spawn_monitor(fn -> Connection.with_connection(pool, run_boot_step) end)

        refute_receive {:DOWN, ^monitor_ref, :process, ^pid, _reason}, 1_000

        stop_waiter(pid)
        stop_unreachable_pool()
      end)

    # The configured database answers, so the wait is on the pool alone.
    assert log =~ "the database answers, but the pool has not connected to it yet"
  end

  describe "__using__/1" do
    test "imports the query and write stages, and aliases the modules the verbs live on" do
      {{:module, module, _binary, _result}, _bindings} =
        Code.eval_string("""
        defmodule Hologram.Test.Fixtures.DB.DataSurface do
          use Hologram.DB

          def query, do: filter(Hologram.Test.Fixtures.Entity.Module2, c: "abc")

          def write, do: put_attribute(Hologram.Test.Fixtures.Entity.Module2.new(), :c, "abc")

          def executor, do: DB.pool_name()

          def job_fields, do: Job.framework_attribute_names()
        end
        """)

      assert module.query() == %Query{
               entity: Module2,
               filter: [{:c, :==, "abc"}]
             }

      assert module.write().__meta__.attribute_ops == %{c: {:put, "abc"}}
      assert module.executor() == pool_name()
      assert module.job_fields() == [:actor_id, :error, :status]
    end
  end

  describe "init/1" do
    test "derives the mapping from the model cache" do
      mapping = mapping()

      on_exit(fn ->
        Model.reset_caches()
        :persistent_term.put(mapping_key(), mapping)
      end)

      Model.put_facts([Module1], [], nil)

      init([])

      assert mapping() == Mapper.derive!([Module1], [])
    end

    # A vanished node's sessions would otherwise stay open on the server for hours, holding the row
    # locks of whatever job they were claiming.
    test "sets the keepalives and the user timeout of each pool connection" do
      statement =
        "SELECT current_setting('tcp_keepalives_idle'), current_setting('tcp_keepalives_interval'), current_setting('tcp_keepalives_count'), current_setting('tcp_user_timeout')"

      assert {:ok, %Postgrex.Result{rows: [["30", "10", "3", user_timeout]]}} =
               Connection.query(statement)

      # A platform without the user timeout keeps it at 0.
      assert user_timeout in ["0", "60000"]
    end

    test "applies the session settings as each pool connection connects" do
      {:ok, {_flags, [%{start: {_pool, :start_link, [{Hologram.DB.Protocol, opts}]}}]}} = init([])

      assert opts[:after_connect] == {Hologram.DB, :apply_session_settings, []}
    end

    test "leaves the given after_connect in place" do
      after_connect = {IO, :inspect, []}

      {:ok, {_flags, [%{start: {_pool, :start_link, [{Hologram.DB.Protocol, opts}]}}]}} =
        init(after_connect: after_connect)

      assert opts[:after_connect] == after_connect
    end

    test "starts only the connection pool in test" do
      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool]
    end

    test "adds the schema reconciliation boot step in dev" do
      System.put_env("HOLOGRAM_ENV", "dev")
      on_exit(fn -> System.delete_env("HOLOGRAM_ENV") end)

      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool, :schema_reconciliation]
    end

    test "adds the migration apply boot step outside dev and test" do
      System.put_env("HOLOGRAM_ENV", "prod")
      on_exit(fn -> System.delete_env("HOLOGRAM_ENV") end)

      # Only dev and test carry default connection options - a prod resolve needs them
      # configured, though nothing connects here (init/1 only builds the child specs).
      database_config = Application.get_env(:hologram, :database, [])

      Application.put_env(:hologram, :database,
        database: "my_app_prod",
        host: "db.internal",
        password: "secret",
        user: "my_app"
      )

      on_exit(fn -> Application.put_env(:hologram, :database, database_config) end)

      {:ok, {_flags, children}} = init([])

      assert Enum.map(children, & &1.id) == [DBConnection.ConnectionPool, :migrations]
    end
  end

  describe "mapping/0" do
    test "returns the mapping derived from the discovered entity types" do
      assert mapping() == Mapper.derive!(Reflection.list_entities(), Reflection.list_roles())
    end

    test "raises when the model is under a hold" do
      on_exit(&Model.release/0)

      Model.hold()

      assert_error Hologram.StaleModelError, @stale_model_msg, fn -> mapping() end
    end
  end

  describe "migrate_at_boot/0" do
    test "waits for the database first" do
      assert_waits_for_database(:migrate_at_boot)
    end
  end

  describe "pool_name/0" do
    test "names a running connection pool that executes queries" do
      assert Postgrex.query!(pool_name(), "SELECT 1", []).rows == [[1]]
    end
  end

  describe "put_boot_facts/0" do
    test "derives the mapping from the model cache" do
      mapping = mapping()

      on_exit(fn ->
        Model.reset_caches()
        :persistent_term.put(mapping_key(), mapping)
      end)

      Model.put_facts([Module1], [], nil)

      assert put_boot_facts() == :ok

      assert mapping() == Mapper.derive!([Module1], [])
    end
  end

  describe "reconcile_at_boot/0" do
    test "waits for the database first" do
      assert_waits_for_database(:reconcile_at_boot)
    end
  end

  describe "reconciliation_context/0" do
    test "carries the mapping, guard facts, and marker diagnostics" do
      context = reconciliation_context()

      assert context.mapping == mapping()
      assert context.otp_app == "hologram"
      assert context.env == "test"
      assert context.hologram_version == Mix.Project.config()[:version]
      assert %DateTime{} = context.timestamp
    end
  end

  describe "apply_session_settings/1" do
    # A server that lacks a setting would otherwise leave the pool without a connection it could
    # use - each one raising on connect, then trying again.
    test "warns rather than raising when the server refuses the settings" do
      connection = start_supervised!({Postgrex, Config.connection_opts(pool_size: 1)})
      Postgrex.query!(connection, "BEGIN", [])
      {:error, _error} = Postgrex.query(connection, "SELECT 1 / 0", [])

      log = capture_log(fn -> assert apply_session_settings(connection) == :ok end)

      assert log =~ "the database refused the session's keepalive settings"
    end
  end

  describe "await_database/1" do
    test "returns :ok when the database answers" do
      assert await_database(retry_interval_ms: 10) == :ok
    end

    test "waits while the database cannot be reached, and returns once it answers" do
      proxy = start_supervised!(TCPProxy)
      port = TCPProxy.port(proxy)

      log =
        capture_log(fn ->
          pool = start_unreachable_pool(proxy)

          task =
            Task.async(fn ->
              Connection.with_connection(pool, fn ->
                await_database(
                  connection_opts: Config.connection_opts(port: port),
                  retry_interval_ms: 20
                )
              end)
            end)

          refute Task.yield(task, 200)

          TCPProxy.open(proxy)

          assert Task.await(task) == :ok

          stop_unreachable_pool()
        end)

      assert log =~ "the database cannot be reached yet, trying again in 20 ms"
      assert log =~ "tcp recv (idle): closed"
    end

    test "waits while the database is starting up" do
      connection_opts = Config.connection_opts(port: start_starting_up_server())

      log =
        capture_log(fn ->
          pool = start_unreachable_pool()

          {pid, monitor_ref} =
            spawn_monitor(fn ->
              Connection.with_connection(pool, fn ->
                await_database(connection_opts: connection_opts, retry_interval_ms: 10)
              end)
            end)

          refute_receive {:DOWN, ^monitor_ref, :process, ^pid, _reason}, 1_000

          stop_waiter(pid)
          stop_unreachable_pool()
        end)

      assert log =~ "the database cannot be reached yet"
      assert log =~ "the database system is starting up"
    end

    # A server that is down and settings that are wrong look the same through the pool, and only
    # the first is worth waiting for.
    test "raises when the database cannot be connected to for a reason other than being away" do
      connection_opts = Config.connection_opts(database: "hologram_no_such_database")

      capture_log(fn ->
        pool = start_unreachable_pool()

        assert_raise Postgrex.Error, ~r/hologram_no_such_database/, fn ->
          Connection.with_connection(pool, fn ->
            await_database(connection_opts: connection_opts, retry_interval_ms: 10)
          end)
        end

        stop_unreachable_pool()
      end)
    end

    # Waiting is for a database that is away - one that answers with an error would answer the
    # same way on every try.
    test "raises an error other than a connection error" do
      connection = start_supervised!({Postgrex, Config.connection_opts(pool_size: 1)})
      Postgrex.query!(connection, "BEGIN", [])
      {:error, _error} = Postgrex.query(connection, "SELECT 1 / 0", [])

      assert_raise Postgrex.Error, ~r/current transaction is aborted/, fn ->
        Connection.with_connection(connection, fn -> await_database(retry_interval_ms: 10) end)
      end
    end
  end

  describe "create/1" do
    test "evaluates the claim under an acting user" do
      entity = Module1.new()

      expected_msg =
        ~s(not allowed to create Hologram.Test.Fixtures.Entity.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(Entity.generate_id(), fn -> create(entity) end)
      end
    end

    # Both shapes in one test: the first create binds {:ok, _} or the match fails, and the
    # second pins the violation travelling out through the gateway unchanged.
    test "returns the unique violation from the write itself" do
      {:ok, _entity} =
        %{slug: "x"}
        |> Module19.new()
        |> create()

      result =
        %{slug: "x"}
        |> Module19.new()
        |> create()

      assert result == {:error, %{slug: [:unique]}}
    end

    test "returns a value violation and a taken unique value in one map" do
      {:ok, _entity} =
        %{code: "gateway_taken", slug: "gateway_a"}
        |> Module19.new()
        |> create()

      assert create(Module19.new(code: "gateway_taken", slug: 123)) ==
               {:error, %{code: [:unique], slug: [type: :string]}}
    end

    test "returns a missing reference target" do
      assert create(Module3.new(c_id: Entity.generate_id())) ==
               {:error, %{c_id: [:not_found]}}
    end

    test "returns every missing reference target" do
      assert create(Module3.new(b_id: Entity.generate_id(), c_id: Entity.generate_id())) ==
               {:error, %{b_id: [:not_found], c_id: [:not_found]}}
    end

    test "rejects role grants" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error MisuseError, expected_msg, fn -> create(%RoleGrant{}) end
    end

    test "rejects jobs" do
      expected_msg =
        "Hologram.Test.Fixtures.Job.Module1 is a job type - create it through Job.create/2, which records who enqueued it so the worker can run it as them after the transaction commits"

      assert_error MisuseError, expected_msg, fn -> create(JobModule1.new()) end
    end
  end

  describe "create!/1" do
    test "returns the created entity" do
      entity = create!(Module1.new())

      assert entity.created_at
      assert read(Module1, entity.id).id == entity.id
    end

    test "raises a write error naming every value violation" do
      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module2:
          * attribute :b must be of type :integer, got: "nope"
          * attribute :c is required\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        %{b: "nope"}
        |> Module2.new()
        |> create!()
      end

      error =
        try do
          %{b: "nope"}
          |> Module2.new()
          |> create!()
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{b: [type: :integer], c: [:required]}
    end

    # assert_error sees the message and nothing else, so the reason field - what the plain
    # variant would have returned - is caught and asserted separately.
    test "raises naming the taken value beside the value violation" do
      {:ok, _entity} =
        %{code: "bang_taken", slug: "bang_a"}
        |> Module19.new()
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module19:
          * attribute :code "bang_taken" is already taken
          * attribute :slug must be of type :string, got: 123\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        create!(Module19.new(code: "bang_taken", slug: 123))
      end
    end

    test "raises a write error when a unique attribute's value is taken" do
      {:ok, _entity} =
        %{slug: "x"}
        |> Module19.new()
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module19:
          * attribute :slug "x" is already taken\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        %{slug: "x"}
        |> Module19.new()
        |> create!()
      end

      error =
        try do
          %{slug: "x"}
          |> Module19.new()
          |> create!()
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{slug: [:unique]}
    end

    test "raises a write error naming a taken key once, with the values given" do
      create!(Module53.new(a: "bang_key_a", b: "bang_key_b"))

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module53:
          * key [:a, :b] is already taken (a "bang_key_a", b "bang_key_b")\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        create!(Module53.new(a: "bang_key_a", b: "bang_key_b"))
      end
    end

    test "raises a write error naming a taken unique reference" do
      channel =
        %{name: "general"}
        |> Module26.new()
        |> create!()

      %{channel_id: channel.id, summary: "first"}
      |> Module27.new()
      |> create!()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module27:
          * reference :channel_id "#{channel.id}" is already taken\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        %{channel_id: channel.id, summary: "second"}
        |> Module27.new()
        |> create!()
      end
    end

    test "raises naming the missing target" do
      gone_id = Entity.generate_id()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module13:
          * reference :parent_id "#{gone_id}" names no existing entity\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        create!(Module13.new(parent_id: gone_id, title: "t"))
      end

      error =
        try do
          create!(Module13.new(parent_id: gone_id, title: "t"))
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{parent_id: [:not_found]}
    end

    test "raises naming the missing target beside the value violation" do
      gone_id = Entity.generate_id()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module13:
          * reference :parent_id "#{gone_id}" names no existing entity
          * attribute :title is required\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        create!(Module13.new(parent_id: gone_id, title: nil))
      end
    end
  end

  describe "delete/2" do
    test "rejects role grants" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error MisuseError, expected_msg, fn ->
        delete(RoleGrant, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
      end
    end
  end

  describe "delete/1" do
    test "deletes the given entity struct" do
      {:ok, entity} = create(Module1.new())

      assert delete(entity) == :ok
      assert read(Module1, entity.id) == nil
    end
  end

  describe "delete!/1" do
    test "deletes the given entity struct" do
      {:ok, entity} = create(Module1.new())

      assert delete!(entity) == :ok
      assert read(Module1, entity.id) == nil
    end

    test "lets a denied claim propagate" do
      {:ok, entity} = create(Module1.new())

      expected_msg =
        ~s(not allowed to delete Hologram.Test.Fixtures.Entity.Module1 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(Entity.generate_id(), fn -> delete!(entity) end)
      end

      assert read(Module1, entity.id) != nil
    end

    test "raises on a restricted delete" do
      {:ok, target} = create(Module1.new())

      {:ok, source} =
        %{c_id: target.id}
        |> Module3.new()
        |> create()

      expected_msg =
        "cannot delete Hologram.Test.Fixtures.Entity.Module1 #{inspect(target.id)} - " <>
          "still referenced by Hologram.Test.Fixtures.Entity.Module3 through :c"

      assert_error WriteError, expected_msg, fn -> delete!(target) end

      assert read(Module3, source.id) != nil
    end

    test "raises on a restricted delete inside a transaction" do
      {:ok, target} = create(Module1.new())

      {:ok, _source} =
        %{c_id: target.id}
        |> Module3.new()
        |> create()

      expected_msg =
        "cannot delete Hologram.Test.Fixtures.Entity.Module1 #{inspect(target.id)} - " <>
          "still referenced by Hologram.Test.Fixtures.Entity.Module3 through :c"

      assert_error WriteError, expected_msg, fn ->
        transaction(fn -> delete!(target) end)
      end
    end
  end

  describe "delete!/2" do
    test "returns :ok" do
      {:ok, entity} = create(Module1.new())

      assert delete!(Module1, entity.id) == :ok
      assert read(Module1, entity.id) == nil
    end

    test "raises a write error when another entity references the row" do
      {:ok, target} = create(Module1.new())

      {:ok, _referencing} =
        %{c_id: target.id}
        |> Module3.new()
        |> create()

      expected_msg =
        ~s(cannot delete Hologram.Test.Fixtures.Entity.Module1 "#{target.id}" - ) <>
          "still referenced by Hologram.Test.Fixtures.Entity.Module3 through :c"

      assert_error Hologram.WriteError, expected_msg, fn ->
        delete!(Module1, target.id)
      end

      error =
        try do
          delete!(Module1, target.id)
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{referenced_by: Module3, relationship: :c}
      assert read(Module1, target.id) == target
    end
  end

  describe "join_table_name/2" do
    test "returns the join table of a to-many relationship" do
      assert join_table_name(Module3, :a) == "test_fixtures_entity_module3_a_$join"
    end

    test "raises for a to-one relationship" do
      expected_msg =
        "relationship :c of Hologram.Test.Fixtures.Entity.Module3 is a to-one relationship, " <>
          "stored as the c_id column of the entity's own table - a join table backs a to-many " <>
          "relationship only"

      assert_error MisuseError, expected_msg, fn -> join_table_name(Module3, :c) end
    end

    test "raises for an inverse of a to-one" do
      expected_msg =
        "relationship :messages of Hologram.Test.Fixtures.Entity.Module26 is an inverse - it " <>
          "reads the channel_id column of Hologram.Test.Fixtures.Entity.Module28's table, and a " <>
          "join table backs a stored to-many relationship only"

      assert_error MisuseError, expected_msg, fn -> join_table_name(Module26, :messages) end
    end

    test "raises for an inverse of a to-many" do
      expected_msg =
        "relationship :messages of Hologram.Test.Fixtures.Entity.Module29 is an inverse - it " <>
          "reads the join table of the labels relationship of Hologram.Test.Fixtures.Entity.Module28"

      assert_error MisuseError, expected_msg, fn -> join_table_name(Module29, :messages) end
    end

    test "raises for an undeclared relationship" do
      assert_error MisuseError,
                   "Hologram.Test.Fixtures.Entity.Module3 declares no relationship :x",
                   fn -> join_table_name(Module3, :x) end
    end

    test "raises for a module that is not an entity type" do
      expected_msg =
        "Hologram.Reflection is not an entity type module - join_table_name/2 takes an entity " <>
          "type and the name of one of its to-many relationships"

      assert_error MisuseError, expected_msg, fn -> join_table_name(Reflection, :a) end
    end
  end

  describe "refusal_lines/3" do
    # One line per key, in the place of the first of its fields, then the field's own lines.
    test "writes a taken key once, beside the other reasons its fields carry" do
      violations = %{
        a: [unique: [:a, :b]],
        b: [unique: [:a, :b], unique: [:b, :d]],
        d: [unique: [:b, :d]],
        kind: [unique: [:kind, :slug]],
        slug: [:unique, {:unique, [:kind, :slug]}]
      }

      values = %{a: "x", b: "y", d: "z", kind: :y, slug: "s"}

      assert refusal_lines(Module53, violations, values) ==
               normalize_newlines("""
                 * key [:a, :b] is already taken (a "x", b "y")
                 * key [:b, :d] is already taken (b "y", d "z")
                 * key [:kind, :slug] is already taken (kind :y, slug "s")
                 * attribute :slug "s" is already taken\
               """)
    end

    # An update moving a field by an amount names no value for it.
    test "leaves out the values the write did not give" do
      assert refusal_lines(Module19, %{code: [:unique]}, %{}) ==
               "  * attribute :code is already taken"

      violations = %{count: [unique: [:name, :count]], name: [unique: [:name, :count]]}

      assert refusal_lines(Module54, violations, %{}) ==
               "  * key [:name, :count] is already taken"
    end
  end

  describe "reload/2" do
    test "re-derives the mapping and reconciles the schema" do
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_system" CASCADE))
      {:ok, _result} = Connection.query(~s(DROP SCHEMA "hologram_data" CASCADE))

      assert reload(Reflection.list_entities(), Reflection.list_roles()) == :ok

      assert Introspection.schema() == Schema.from_mapping(mapping())
    end

    test "derives the mapping from the given modules" do
      expected_msg =
        normalize_newlines("""
        colliding table names - rename modules so that every entity type derives a unique table name:
          * table name "blog_post" is derived from Hologram.Blog.Post, Hologram.BlogPost\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        reload([Hologram.Blog.Post, Hologram.BlogPost], [])
      end
    end
  end

  describe "schema_name/0" do
    test "returns the data schema" do
      assert schema_name() == "hologram_data"
    end
  end

  describe "sql/3" do
    test "reads rows the sandbox transaction wrote" do
      {:ok, _entity} = create(Module1.new())

      assert sql(
               ~s|SELECT count(*) AS "count" FROM "hologram_data"."test_fixtures_entity_module1"|
             ) ==
               {:ok, %{columns: ["count"], rows: [[1]]}}
    end

    test "leaves the sandbox transaction writable" do
      {:ok, _result} = sql(~s|SELECT 1 AS "one"|)

      assert {:ok, %Module1{}} = create(Module1.new())
    end

    test "reads an entity id as the string the entity carries" do
      {:ok, entity} = create(Module1.new())

      statement =
        ~s|SELECT "id" FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

      assert sql(statement, [entity.id]) == {:ok, %{columns: ["id"], rows: [[entity.id]]}}
    end

    test "refuses a delete" do
      assert {:error, %SQLError{code: :read_only_sql_transaction}} =
               sql(~s|DELETE FROM "hologram_data"."test_fixtures_entity_module1"|)
    end
  end

  describe "sql!/3" do
    test "returns the result" do
      assert sql!(~s|SELECT 1 AS "one"|) == %{columns: ["one"], rows: [[1]]}
    end

    test "raises on a refused delete" do
      expected_msg =
        "DB.sql/3 can only read data, and this statement writes it (PostgreSQL: cannot execute " <>
          "DELETE in a read-only transaction). Use DB.create/1, DB.update/3 or DB.delete/2 to " <>
          "write, so that the change reaches the sync and the clients."

      assert_error SQLError, expected_msg, fn ->
        sql!(~s|DELETE FROM "hologram_data"."test_fixtures_entity_module1"|)
      end
    end

    test "raises on a param that does not fit its placeholder" do
      assert_error MisuseError,
                   "DB.sql/3 got 0 params for a statement with 1 placeholder",
                   fn ->
                     sql!(~s|SELECT $1::uuid AS "id"|)
                   end
    end
  end

  describe "table_name/1" do
    test "returns the table of an entity type" do
      assert table_name(Module1) == "test_fixtures_entity_module1"
    end

    test "returns the pinned table of the role grant store" do
      assert table_name(RoleGrant) == "hologram_role_grant"
    end

    test "returns the table of a job type" do
      assert table_name(JobModule1) == "test_fixtures_job_module1"
    end

    test "raises for a module that is not an entity type" do
      assert_error MisuseError,
                   "Hologram.Reflection is not an entity type module - table_name/1 takes an entity type",
                   fn -> table_name(Reflection) end
    end
  end

  describe "transaction/2" do
    test "completes a refused write's map inside a transaction" do
      {:ok, _entity} =
        %{code: "nested_taken", slug: "nested_taken"}
        |> Module19.new()
        |> create()

      result =
        transaction(fn ->
          %{code: "nested_taken", slug: "nested_taken"}
          |> Module19.new()
          |> create()
        end)

      assert result == {:ok, {:error, %{code: [:unique], slug: [:unique]}}}
    end

    test "returns a refused update's violations inside a transaction" do
      {:ok, first} =
        %{slug: "nested_update_held"}
        |> Module19.new()
        |> create()

      {:ok, second} =
        %{slug: "nested_update_other"}
        |> Module19.new()
        |> create()

      result =
        transaction(fn ->
          refusal = update(Module19, second.id, slug: first.slug)

          {refusal, update(Module19, second.id, slug: "nested_update_free")}
        end)

      assert result == {:ok, {{:error, %{slug: [:unique]}}, :ok}}
    end

    test "returns a refused write's violations inside a transaction and keeps it usable" do
      {:ok, _entity} =
        %{slug: "nested_held"}
        |> Module19.new()
        |> create()

      result =
        transaction(fn ->
          refusal =
            %{slug: "nested_held"}
            |> Module19.new()
            |> create()

          {:ok, other} =
            %{slug: "nested_other"}
            |> Module19.new()
            |> create()

          {refusal, other.id}
        end)

      assert {:ok, {{:error, %{slug: [:unique]}}, other_id}} = result
      assert read(Module19, other_id)
    end

    test "returns a restricted delete's referencer inside a transaction" do
      {:ok, target} = create(Module1.new())

      {:ok, _referencing} =
        %{c_id: target.id}
        |> Module3.new()
        |> create()

      result =
        transaction(fn ->
          refusal = delete(Module1, target.id)

          {refusal, read(Module1, target.id)}
        end)

      assert result == {:ok, {{:error, %{referenced_by: Module3, relationship: :c}}, target}}
    end

    test "returns a value violation inside a transaction" do
      result =
        transaction(fn ->
          %{b: "nope"}
          |> Module2.new()
          |> create()
        end)

      assert result == {:ok, {:error, %{b: [type: :integer], c: [:required]}}}
    end

    test "raises through the bang for a value violation inside a transaction" do
      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module2:
          * attribute :b must be of type :integer, got: "nope"
          * attribute :c is required\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        transaction(fn ->
          %{b: "nope"}
          |> Module2.new()
          |> create!()
        end)
      end
    end

    test "raises through the bang inside a transaction and rolls it back" do
      {:ok, _entity} =
        %{slug: "nested_bang_held"}
        |> Module19.new()
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot create Hologram.Test.Fixtures.Entity.Module19:
          * attribute :slug "nested_bang_held" is already taken\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        transaction(fn ->
          {:ok, earlier} =
            %{slug: "nested_bang_earlier"}
            |> Module19.new()
            |> create()

          Process.put(:earlier_id, earlier.id)

          %{slug: "nested_bang_held"}
          |> Module19.new()
          |> create!()
        end)
      end

      assert read(Module19, Process.get(:earlier_id)) == nil
    end
  end

  describe "update/3" do
    test "returns the unique violation from the write itself" do
      {:ok, first} =
        %{slug: "held"}
        |> Module19.new()
        |> create()

      {:ok, second} =
        %{slug: "other"}
        |> Module19.new()
        |> create()

      assert update(Module19, second.id, slug: first.slug) == {:error, %{slug: [:unique]}}
    end

    test "returns a value violation and a taken unique value in one map" do
      {:ok, first} =
        %{code: "gateway_update_taken", slug: "gateway_update_a"}
        |> Module19.new()
        |> create()

      {:ok, second} =
        %{code: "gateway_update_free", slug: "gateway_update_b"}
        |> Module19.new()
        |> create()

      assert update(Module19, second.id, %{code: first.code, slug: 123}) ==
               {:error, %{code: [:unique], slug: [type: :string]}}
    end

    test "returns a missing reference target" do
      {:ok, target_entity} = create(Module1.new())

      {:ok, entity} =
        %{c_id: target_entity.id}
        |> Module3.new()
        |> create()

      assert update(Module3, entity.id, %{c_id: Entity.generate_id()}) ==
               {:error, %{c_id: [:not_found]}}
    end

    test "returns every missing reference target" do
      {:ok, target_entity} = create(Module1.new())

      {:ok, entity} =
        %{c_id: target_entity.id}
        |> Module3.new()
        |> create()

      changes = %{b_id: Entity.generate_id(), c_id: Entity.generate_id()}

      assert update(Module3, entity.id, changes) ==
               {:error, %{b_id: [:not_found], c_id: [:not_found]}}
    end

    test "rejects role grants" do
      expected_msg = "role grants are written only through grant_role/revoke_role"

      assert_error MisuseError, expected_msg, fn ->
        update(RoleGrant, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f", role: :owner)
      end
    end

    test "raises on a change to a derived field" do
      {:ok, entity} = create(Module32.new(name: "general"))

      expected_msg =
        "invalid changes for Hologram.Test.Fixtures.Entity.Module32 - :message_count is a derived field of Hologram.Test.Fixtures.Entity.Module32 - it's computed from its definition, so it's read-only"

      assert_error MisuseError, expected_msg, fn ->
        update(Module32, entity.id, message_count: 3)
      end
    end
  end

  describe "update!/1" do
    test "writes the changes recorded on the struct" do
      {:ok, entity} =
        %{c: "before"}
        |> Module2.new()
        |> create()

      assert entity
             |> put_attribute(:c, "after")
             |> update!() == :ok

      assert read(Module2, entity.id).c == "after"
    end

    test "lets a denied claim propagate" do
      {:ok, entity} =
        %{c: "before"}
        |> Module2.new()
        |> create()

      expected_msg =
        ~s(not allowed to update Hologram.Test.Fixtures.Entity.Module2 "#{entity.id}")

      assert_error AccessDeniedError, expected_msg, fn ->
        as_user(Entity.generate_id(), fn ->
          entity
          |> put_attribute(:c, "after")
          |> update!()
        end)
      end

      assert read(Module2, entity.id).c == "before"
    end

    test "raises on a refused value" do
      {:ok, entity} =
        %{slug: "taken"}
        |> Module19.new()
        |> create()

      {:ok, other_entity} =
        %{slug: "free"}
        |> Module19.new()
        |> create()

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module19 #{inspect(other_entity.id)}:\n" <>
          ~s|  * attribute :slug "taken" is already taken|

      assert_error WriteError, expected_msg, fn ->
        other_entity
        |> put_attribute(:slug, "taken")
        |> update!()
      end

      assert read(Module19, entity.id).slug == "taken"
    end

    # An update gives only its changes, so the key's line spells out the changed field and
    # names the rest by the key.
    test "raises naming a taken key with the changed values" do
      create!(Module53.new(a: "update_key_a", b: "update_key_b"))
      entity = create!(Module53.new(a: "update_key_a", b: "update_key_free"))

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module53 #{inspect(entity.id)}:\n" <>
          ~s|  * key [:a, :b] is already taken (b "update_key_b")|

      assert_error WriteError, expected_msg, fn ->
        entity
        |> put_attribute(:b, "update_key_b")
        |> update!()
      end
    end

    # A move names no value, so the key's line gives none.
    test "raises naming a key a counter's move repeats" do
      create!(Module54.new(count: 3, name: "moved_bang"))
      entity = create!(Module54.new(count: 4, name: "moved_bang"))

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module54 #{inspect(entity.id)}:\n" <>
          "  * key [:name, :count] is already taken"

      assert_error WriteError, expected_msg, fn ->
        entity
        |> decrement(:count, 1)
        |> update!()
      end
    end

    test "raises naming a moved attribute's refused result" do
      {:ok, entity} =
        %{count: 1}
        |> Module10.new()
        |> create()

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module10 #{inspect(entity.id)}:\n" <>
          "  * attribute :count must be at least 1"

      assert_error WriteError, expected_msg, fn ->
        entity
        |> decrement(:count, 1)
        |> update!()
      end

      assert read(Module10, entity.id).count == 1
    end

    test "names the value the write used, not the one the struct holds" do
      {:ok, _entity} =
        %{slug: "written"}
        |> Module19.new()
        |> create()

      {:ok, other_entity} =
        %{slug: "spare"}
        |> Module19.new()
        |> create()

      # The recorded change is what the write uses - a field set directly on the struct
      # afterwards is neither written nor named in the refusal.
      entity = %{put_attribute(other_entity, :slug, "written") | slug: "set directly"}

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module19 #{inspect(other_entity.id)}:\n" <>
          ~s|  * attribute :slug "written" is already taken|

      assert_error WriteError, expected_msg, fn -> update!(entity) end
    end

    test "raises on a refused value inside a transaction" do
      {:ok, _entity} =
        %{slug: "held"}
        |> Module19.new()
        |> create()

      {:ok, other_entity} =
        %{slug: "spare"}
        |> Module19.new()
        |> create()

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module19 #{inspect(other_entity.id)}:\n" <>
          ~s|  * attribute :slug "held" is already taken|

      assert_error WriteError, expected_msg, fn ->
        transaction(fn ->
          other_entity
          |> put_attribute(:slug, "held")
          |> update!()
        end)
      end
    end
  end

  describe "update!/3" do
    test "returns :ok" do
      {:ok, entity} =
        %{slug: "before"}
        |> Module19.new()
        |> create()

      assert update!(Module19, entity.id, slug: "after") == :ok
    end

    test "raises a write error naming every change violation" do
      {:ok, entity} =
        %{a: true, c: "some text"}
        |> Module2.new()
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot update Hologram.Test.Fixtures.Entity.Module2 "#{entity.id}":
          * attribute :b must be of type :integer, got: "nope"\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        update!(Module2, entity.id, b: "nope")
      end

      error =
        try do
          update!(Module2, entity.id, b: "nope")
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{b: [type: :integer]}
    end

    test "raises a write error when the new value is taken" do
      {:ok, first} =
        %{slug: "held"}
        |> Module19.new()
        |> create()

      {:ok, second} =
        %{slug: "other"}
        |> Module19.new()
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot update Hologram.Test.Fixtures.Entity.Module19 "#{second.id}":
          * attribute :slug "held" is already taken\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        update!(Module19, second.id, slug: first.slug)
      end

      error =
        try do
          update!(Module19, second.id, slug: first.slug)
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{slug: [:unique]}
    end

    test "raises naming the missing target" do
      gone_id = Entity.generate_id()

      {:ok, target_entity} = create(Module1.new())

      {:ok, entity} =
        %{c_id: target_entity.id}
        |> Module3.new()
        |> create()

      expected_msg =
        normalize_newlines("""
        cannot update Hologram.Test.Fixtures.Entity.Module3 "#{entity.id}":
          * reference :c_id "#{gone_id}" names no existing entity\
        """)

      assert_error Hologram.WriteError, expected_msg, fn ->
        update!(Module3, entity.id, c_id: gone_id)
      end

      error =
        try do
          update!(Module3, entity.id, c_id: gone_id)
        rescue
          error in Hologram.WriteError -> error
        end

      assert error.reason == %{c_id: [:not_found]}
    end
  end

  describe "update/1" do
    test "writes the changes recorded on the struct" do
      {:ok, entity} =
        %{c: "before"}
        |> Module2.new()
        |> create()

      assert entity
             |> put_attribute(:c, "after")
             |> update() == :ok

      assert read(Module2, entity.id).c == "after"
    end

    test "raises a teaching error for a struct carrying nothing recorded" do
      {:ok, entity} = create(Module1.new())

      expected_msg =
        "update takes recorded changes - put values with put_attribute, move counters with " <>
          "increment or decrement, and edges with add_relationship or delete_relationship. " <>
          "A field set directly on the struct is not recorded: writing the whole struct " <>
          "would overwrite concurrent changes to fields you didn't touch."

      assert_error MisuseError, expected_msg, fn -> update(entity) end
    end
  end
end
