defmodule Mix.Tasks.Holo.Check.Migration do
  @shortdoc "Checks the migration history against the model"

  @moduledoc """
  Validates the project's migration history against its model - the gate a CI
  pipeline runs so that a model change whose migration was never generated cannot
  merge.

      $ mix holo.check.migration

  Three checks, and any failure exits non-zero: no draft still holds resolve! ops,
  the history folds to the model, and the replayed history produces the model's
  schema on a scratch database.
  """

  use Mix.Task

  alias Hologram.Entity.Model
  alias Hologram.Migration.Checker
  alias Hologram.Migration.Loader
  alias Hologram.Reflection

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run(_args) do
    model = Model.from_modules(Reflection.list_entities(), Reflection.list_roles())

    Checker.check!(Loader.migrations_dir(), model)

    print("migrations check passed")
  rescue
    # Exception.message/1 rather than the :message field - Postgrex.Error keeps its detail
    # in :postgres and leaves :message nil, which Mix.raise/1 will not take.
    error in [Hologram.CompileError, Postgrex.Error, RuntimeError] ->
      error
      |> Exception.message()
      |> Mix.raise()
  end

  defp print(output) do
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(output)
  end
end
