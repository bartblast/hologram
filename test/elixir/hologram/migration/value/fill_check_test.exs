defmodule Hologram.Migration.Value.FillCheckTest do
  # async: false - every module of the scratch tier opens raw sessions beside its scratch
  # connection.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Migration.Value.FillCheck
  import Hologram.Migrator, only: [run: 3]

  alias Hologram.DB.Connection
  alias Hologram.Entity.Model

  @context %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-08-13 09:15:22.000000Z]
  }

  @ops [
    %{op: :create_entity, entity: MyApp.Task, line: 1},
    %{op: :add_attribute, entity: MyApp.Task, name: :title, type: :string, opts: [], line: 2}
  ]

  @fill %{
    column: "title",
    max_bytes: nil,
    member: :title,
    rules: [max_length: 2],
    table: "my_app_task",
    type: :string
  }

  defp insert_task(title, id \\ "018f0000-0000-7000-8000-000000000000") do
    {:ok, _result} =
      Connection.query(
        ~s|INSERT INTO "hologram_data"."my_app_task" ("id", "title", "created_at", | <>
          ~s|"server_created_at", "server_updated_at", "updated_at", "$revisions") | <>
          ~s|VALUES ($2::text::uuid, $1, now(), now(), now(), now(), '{}')|,
        [title, id]
      )
  end

  defp prepare do
    migration = %{version: "20260813091522", path: "app/migrations/1.ex", ops: @ops}

    assert run([migration], Model.fold(Model.empty(), @ops), @context) == :ok
  end

  describe "create_filled_ids!/0, keep_filled_ids!/1 and drop_filled_ids!/0" do
    test "use the session's own table when the search path puts another of its name first", %{
      scratch: scratch
    } do
      route(scratch, fn ->
        result =
          Connection.transaction(fn ->
            {:ok, _result} = Connection.query(~s|CREATE TABLE public."$fill_ids" (id uuid)|)
            {:ok, _result} = Connection.query("SET LOCAL search_path TO public, pg_temp")

            create_filled_ids!()
            keep_filled_ids!(["018f0000-0000-7000-8000-000000000000"])

            {:ok, %{rows: kept}} = Connection.query(~s|SELECT count(*) FROM pg_temp."$fill_ids"|)

            drop_filled_ids!()

            {:ok, %{rows: dropped}} =
              Connection.query(~s|SELECT to_regclass('pg_temp."$fill_ids"')|)

            {:ok, %{rows: other}} = Connection.query(~s|SELECT count(*) FROM public."$fill_ids"|)

            Connection.rollback({kept, dropped, other})
          end)

        assert result == {:error, {[[1]], [[nil]], [[0]]}}
      end)
    end

    test "raise the database's own error when the table can't be created", %{scratch: scratch} do
      route(scratch, fn ->
        Connection.transaction(fn ->
          create_filled_ids!()

          assert_raise Postgrex.Error, ~r/already exists/, fn -> create_filled_ids!() end

          Connection.rollback(:done)
        end)
      end)
    end
  end

  describe "check!/2" do
    test "doesn't read a table when the member declares no rule and no bound" do
      assert check!(%{@fill | rules: [optional: true], table: "no_such_table"}) == :ok
    end

    test "doesn't bound a member that isn't a string yet" do
      fill = %{@fill | max_bytes: 10, rules: [values: [:a]], table: "no_such_table", type: :enum}

      assert check!(fill) == :ok
    end

    test "reads a row whose id is all zeros", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        insert_task("longer", "00000000-0000-0000-0000-000000000000")

        assert_raise RuntimeError, ~r/must be at most 2 characters \(1 row\)/, fn ->
          check!(@fill)
        end
      end)
    end

    test "counts the broken rows across pages", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        ["ok", "long", "longer", "longest"]
        |> Enum.with_index(1)
        |> Enum.each(fn {title, index} ->
          insert_task(title, "018f0000-0000-7000-8000-00000000000#{index}")
        end)

        assert_raise RuntimeError, ~r/must be at most 2 characters \(3 rows\)/, fn ->
          check!(@fill, page_size: 1)
        end
      end)
    end

    test "names each broken rule", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        insert_task("LONG")

        fill = %{@fill | rules: [format: ~r/^[a-z]+$/, max_length: 2]}

        assert_raise RuntimeError, ~r/must be at most 2 characters \(1 row\), must match/, fn ->
          check!(fill)
        end
      end)
    end

    test "passes values within the rules", %{scratch: scratch} do
      route(scratch, fn ->
        prepare()

        insert_task("ok")

        assert check!(@fill) == :ok
      end)
    end
  end
end
