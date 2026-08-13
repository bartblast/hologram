defmodule Hologram.Migration.ShadowVerifierTest do
  # async: false - the scratch database is a per-suite singleton (the configured name
  # + "_shadow"), so concurrent verifications would tread on each other.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Migration.ShadowVerifier

  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.Entity.Model

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
      opts: [],
      line: 5
    }

    Model.empty()
    |> Model.fold(@ops)
    |> Model.fold([done_op])
  end

  defp shadow_database_exists? do
    database_opts =
      :hologram
      |> Application.get_env(:database, [])
      |> Config.resolve!(:test)

    statement = "SELECT 1 FROM pg_database WHERE datname = $1"

    {:ok, %{rows: rows}} =
      Connection.query(statement, [database_opts[:database] <> "_shadow"])

    rows != []
  end

  describe "verify!/2" do
    test "passes a chain producing the model's schema" do
      model = Model.fold(Model.empty(), @ops)

      assert verify!(@migrations, model) == :ok
    end

    test "drops the scratch database after a pass" do
      model = Model.fold(Model.empty(), @ops)
      verify!(@migrations, model)

      refute shadow_database_exists?()
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
