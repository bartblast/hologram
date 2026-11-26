defmodule Hologram.Mutation.UnstorableTest do
  # async: false - each test puts a trigger on a table, and the lock that takes would hold up
  # anything else writing to it.
  use Hologram.Test.DatabaseCase, async: false

  import ExUnit.CaptureLog
  import Hologram.Mutation

  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Mutation.Record
  alias Hologram.Runtime.Serializer
  alias Hologram.Server
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Mutation.Module5
  alias Hologram.Test.Fixtures.Mutation.Module8

  @refused_title "a-value-the-log-must-not-show"

  defp create_user do
    %{email: "unstorable@example.com"}
    |> Module14.new()
    |> DB.create!()
  end

  defp create_write(id, title) do
    %{
      "op" => "create",
      "type" => inspect(Module8),
      "id" => id,
      "data" => %{"title" => title},
      "stamp" => System.os_time(:millisecond) * 1024
    }
  end

  defp envelope(writes, replica_id \\ Entity.generate_id()) do
    %{
      "instance_id" => "i1",
      "replica_id" => replica_id,
      "model_hash" => Model.hash(),
      "seq" => 1,
      "writes" => writes
    }
  end

  # Rolled back with the test's transaction.
  defp point_grant_key_at(column, user_id) do
    table = ~s|"hologram_data"."#{Mapper.table_name(RoleGrant)}"|

    {:ok, _result} =
      Connection.query("""
      CREATE FUNCTION public.point_grant_key() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        NEW.#{column} := '#{Entity.id_to_uuid(user_id)}'::uuid;

        RETURN NEW;
      END
      $$
      """)

    {:ok, _result} =
      Connection.query("""
      CREATE TRIGGER point_grant_key BEFORE INSERT ON #{table}
      FOR EACH ROW EXECUTE FUNCTION public.point_grant_key()
      """)

    :ok
  end

  # Makes the database refuse a row holding @refused_title with the given SQLSTATE, the way it would
  # refuse a value no validator knows about. Rolled back with the test's transaction.
  defp refuse_with(code) do
    table = ~s|"hologram_data"."#{Mapper.table_name(Module8)}"|

    {:ok, _result} =
      Connection.query("""
      CREATE FUNCTION public.refuse_unstorable_title() RETURNS trigger LANGUAGE plpgsql AS $$
      BEGIN
        IF NEW.title = '#{@refused_title}' THEN
          RAISE EXCEPTION 'private detail' USING ERRCODE = '#{code}';
        END IF;

        RETURN NEW;
      END
      $$
      """)

    {:ok, _result} =
      Connection.query("""
      CREATE TRIGGER refuse_unstorable_title BEFORE INSERT OR UPDATE ON #{table}
      FOR EACH ROW EXECUTE FUNCTION public.refuse_unstorable_title()
      """)

    :ok
  end

  defp rejected(index, reason) do
    {:ok,
     %{
       "reason" => Serializer.serialize!(reason),
       "status" => "rejected",
       "write" => index
     }}
  end

  test "refuses a create the database can't store, naming the write" do
    refuse_with("22008")
    id = Entity.generate_id()

    capture_log(fn ->
      assert run(envelope([create_write(id, @refused_title)]), %Server{}) ==
               rejected(0, :unstorable)
    end)

    assert EntityOperations.get(Module8, id) == nil
  end

  test "refuses an update the database can't store and leaves the row as it was" do
    row =
      [title: "kept"]
      |> Module8.new()
      |> DB.create!()

    refuse_with("22008")

    write = %{
      "op" => "update",
      "type" => inspect(Module8),
      "id" => row.id,
      "data" => %{"title" => @refused_title},
      "stamp" => row.__meta__.revisions.title + 1_000_000
    }

    capture_log(fn ->
      assert run(envelope([write]), %Server{}) == rejected(0, :unstorable)
    end)

    assert EntityOperations.get(Module8, row.id).title == "kept"
  end

  test "takes back the writes before the refused one" do
    refuse_with("22008")
    first_id = Entity.generate_id()
    writes = [create_write(first_id, "fine"), create_write(Entity.generate_id(), @refused_title)]

    capture_log(fn ->
      assert run(envelope(writes), %Server{}) == rejected(1, :unstorable)
    end)

    assert EntityOperations.get(Module8, first_id) == nil
  end

  test "keeps a signed-in user's refused batch" do
    user = create_user()
    refuse_with("22008")
    replica_id = Entity.generate_id()
    raw = envelope([create_write(Entity.generate_id(), @refused_title)], replica_id)

    capture_log(fn ->
      assert {:ok, %{"status" => "rejected"} = answer} = run(raw, %Server{user_id: user.id})

      assert Record.find(replica_id, 1) == %{actor_id: user.id, result: answer}
    end)

    {:ok, %Postgrex.Result{rows: [[kept]]}} =
      Connection.query(
        ~s|SELECT "envelope" FROM "hologram_system"."mutation" WHERE "replica_id" = $1|,
        [replica_id]
      )

    assert kept == raw
  end

  test "logs the entity type and the code, and nothing of the value" do
    refuse_with("22008")

    log =
      capture_log(fn ->
        run(envelope([create_write(Entity.generate_id(), @refused_title)]), %Server{})
      end)

    assert log =~ inspect(Module8)
    assert log =~ "22008"
    refute log =~ @refused_title
    refute log =~ "private detail"
  end

  # An enum label missing from the Postgres type: the database is out of step with the app, and a
  # deploy can fix it, so the write stays queued rather than being lost.
  test "lets invalid_text_representation through, so the write stays queued" do
    refuse_with("22P02")

    assert_raise Postgrex.Error, ~r/private detail/, fn ->
      run(envelope([create_write(Entity.generate_id(), @refused_title)]), %Server{})
    end
  end

  # A creator's grant names the missing user in two keys, and which one the database reports
  # depends on the names of its triggers. Pointing the other key at a real user makes the one under
  # test the only one that can fail.
  for {reporting, other} <- [{"user_id", "granted_by_id"}, {"granted_by_id", "user_id"}] do
    test "refuses a create by a user whose row is gone when #{reporting} reports it" do
      point_grant_key_at(unquote(other), create_user().id)
      id = Entity.generate_id()

      write = %{
        "op" => "create",
        "type" => inspect(Module5),
        "id" => id,
        "data" => %{"title" => "x"},
        "stamp" => System.os_time(:millisecond) * 1024
      }

      assert run(envelope([write]), %Server{user_id: Entity.generate_id()}) ==
               rejected(0, :actor_not_found)

      assert EntityOperations.get(Module5, id) == nil
    end
  end

  test "lets an error that isn't about a value through" do
    refuse_with("P0001")

    assert_raise Postgrex.Error, ~r/private detail/, fn ->
      run(envelope([create_write(Entity.generate_id(), @refused_title)]), %Server{})
    end
  end
end
