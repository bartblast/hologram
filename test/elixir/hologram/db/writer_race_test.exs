defmodule Hologram.DB.WriterRaceTest do
  # async: false because CREATE TRIGGER locks the table until the test's transaction ends, which
  # would block other tests writing to it and could deadlock with them.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB.Writer
  import Hologram.Query, only: [add_relationship: 3, put_attribute: 3]
  import Hologram.Test, only: [as_user: 2]

  alias Hologram.AccessDeniedError
  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module58, as: ChangedProject
  alias Hologram.Test.Fixtures.Policy.Module59, as: ChangedTask
  alias Hologram.Test.Fixtures.Policy.Module60, as: ChangedLabel

  defp create_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  defp create_changed_task(values \\ %{}) do
    task =
      values
      |> ChangedTask.new()
      |> DB.create!()

    EntityOperations.get(ChangedTask, task.id)
  end

  defp create_changed_project do
    %{archived: false}
    |> ChangedProject.new()
    |> DB.create!()
  end

  defp create_changed_label(blocked) do
    %{blocked: blocked}
    |> ChangedLabel.new()
    |> DB.create!()
  end

  defp uncovered_message(task, field) do
    "not allowed to update #{inspect(ChangedTask)} #{inspect(task.id)} - no allow line that holds covers #{inspect(field)}"
  end

  defp table_of(entity_type) do
    ~s("hologram_data"."#{Map.fetch!(DB.mapping(), entity_type).table}")
  end

  # Stands in for another transaction committing a row between a rule reading that it isn't there
  # and the write's foreign key check. The row copies the given one under the given id.
  defp make_row_appear(timing, written_table, target_type, template, id) do
    target_table = table_of(target_type)

    {:ok, _result} = Connection.query("CREATE TEMP SEQUENCE make_row_appear_fired", [])

    {:ok, _result} =
      Connection.query(
        """
        CREATE FUNCTION pg_temp.make_row_appear() RETURNS trigger LANGUAGE plpgsql AS $body$
        BEGIN
          PERFORM nextval('pg_temp.make_row_appear_fired');

          INSERT INTO #{target_table}
          SELECT (jsonb_populate_record(t, jsonb_build_object('id', '#{Entity.id_to_uuid(id)}'))).*
          FROM #{target_table} t WHERE "id" = '#{Entity.id_to_uuid(template.id)}'
          ON CONFLICT DO NOTHING;

          RETURN NEW;
        END
        $body$
        """,
        []
      )

    {:ok, _result} =
      Connection.query(
        "CREATE TRIGGER make_row_appear #{timing} ON #{written_table} " <>
          "FOR EACH ROW EXECUTE FUNCTION pg_temp.make_row_appear()",
        []
      )

    :ok
  end

  # A sequence's position survives the rollback, so this tells a write that reached the database
  # and was undone from one refused before it ran.
  defp assert_write_reached_database do
    assert {:ok, %{rows: [[true]]}} =
             Connection.query("SELECT is_called FROM pg_temp.make_row_appear_fired", [])
  end

  describe "update/1 when a target appears after its rule read it" do
    test "refuses a reference" do
      user = create_user("appearing_reference@example.com")
      project = create_changed_project()
      template = create_changed_project()
      task = create_changed_task(%{project_id: project.id})
      Auth.grant_role(user, :member, project)
      appearing_id = Entity.generate_id()

      make_row_appear(
        "BEFORE UPDATE",
        table_of(ChangedTask),
        ChangedProject,
        template,
        appearing_id
      )

      assert_error AccessDeniedError, uncovered_message(task, :project), fn ->
        as_user(user, fn -> update(put_attribute(task, :project_id, appearing_id)) end)
      end

      assert_write_reached_database()
      assert EntityOperations.get(ChangedTask, task.id).project_id == project.id
    end

    test "refuses an edge" do
      user = create_user("appearing_edge@example.com")
      template = create_changed_label(true)
      task = create_changed_task()
      appearing_id = Entity.generate_id()
      join_table = ~s("hologram_data"."#{DB.join_table_name(ChangedTask, :labels)}")
      make_row_appear("BEFORE INSERT", join_table, ChangedLabel, template, appearing_id)

      assert_error AccessDeniedError, uncovered_message(task, :labels), fn ->
        as_user(user, fn -> update(add_relationship(task, :labels, appearing_id)) end)
      end

      assert_write_reached_database()
      assert {:ok, %{rows: [[0]]}} = Connection.query("SELECT count(*) FROM #{join_table}", [])
    end
  end

  describe "update/3 when a target appears after its rule read it" do
    test "refuses a reference" do
      user = create_user("appearing_given_reference@example.com")
      project = create_changed_project()
      template = create_changed_project()
      task = create_changed_task(%{project_id: project.id})
      Auth.grant_role(user, :member, project)
      appearing_id = Entity.generate_id()

      make_row_appear(
        "BEFORE UPDATE",
        table_of(ChangedTask),
        ChangedProject,
        template,
        appearing_id
      )

      assert_error AccessDeniedError, uncovered_message(task, :project), fn ->
        as_user(user, fn -> update(ChangedTask, task.id, project_id: appearing_id) end)
      end

      assert_write_reached_database()
      assert EntityOperations.get(ChangedTask, task.id).project_id == project.id
    end
  end
end
