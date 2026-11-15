defmodule Hologram.Migration.Checker do
  @moduledoc false

  alias Hologram.Migration.ShadowVerifier
  alias Hologram.Migrator

  @doc """
  Validates the given migration history against the given model: no draft
  still holds resolve! ops, the history folds to the model, and its replay produces
  the model's schema on a scratch database.

  Returns :ok, or raises naming the first failing check - the unanswered resolve!
  ops with their locations, the uncovered model changes, or the schema differences
  the replay leaves.
  """
  @spec check!(list(%{atom => any}), %{atom => any}) :: :ok
  def check!(migrations, current_model) do
    # The coverage check refuses a draft first, naming each unanswered resolve! op.
    Migrator.check_covered!(migrations, current_model)
    ShadowVerifier.verify!(migrations, current_model)

    :ok
  end
end
