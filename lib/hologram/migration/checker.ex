defmodule Hologram.Migration.Checker do
  @moduledoc false

  alias Hologram.Migration.Loader
  alias Hologram.Migration.ShadowVerifier
  alias Hologram.Migrator

  @doc """
  Validates the given directory's migration history against the given model: no draft
  still holds resolve! ops, the history folds to the model, and its replay produces
  the model's schema on a scratch database.

  Returns :ok, or raises naming the first failing check - the unanswered resolve!
  ops with their locations, the uncovered model changes, or the schema differences
  the replay leaves.
  """
  @spec check!(String.t(), %{atom => any}) :: :ok
  def check!(dir, current_model) do
    migrations = Loader.load_dir!(dir)

    check_resolved!(migrations)
    Migrator.check_covered!(migrations, current_model)
    ShadowVerifier.verify!(migrations, current_model)

    :ok
  end

  defp check_resolved!(migrations) do
    unresolved =
      Enum.flat_map(migrations, fn migration ->
        Enum.map(Loader.unresolved(migration.ops), &{migration.path, &1})
      end)

    if unresolved != [] do
      lines =
        Enum.map_join(unresolved, "\n", fn {path, op} ->
          "  #{path}:#{op.line} - #{inspect(op.kind)}"
        end)

      raise "the migration draft is not resolved yet:\n" <>
              lines <>
              "\nWrite the ops that express what happened, delete the resolve! lines, " <>
              "then finalize with mix holo.gen.migration."
    end

    :ok
  end
end
