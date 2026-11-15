defmodule Mix.Tasks.Holo.Gen.Migration do
  @shortdoc "Generates the migration for uncovered model changes"

  @moduledoc """
  Generates the migration expressing the model changes the migration history does not
  cover yet.

      $ mix holo.gen.migration

  Migrations are modules in the project's `app/migrations/` directory, compiled with the
  app - the task refuses to run when the project does not compile that directory. The new
  file goes there, its module named after the newest migration's namespace, or
  `<App>.Migrations` for the first one, and formatted with the project's formatter.

  The task's behavior follows the state of the migration history: nothing to do when
  the history already produces the model, a new file when it does not, and a refusal
  while a draft still holds unanswered questions - those are answered by editing the
  draft, writing the ops that express what happened and deleting the resolve! line. A draft
  compiles only in dev and test builds - any other build refuses it, so it is answered
  before the app builds for anything else.

  A generated file is never amended: when several small files pile up in one branch,
  delete the unmerged ones and run the task again to get a single consolidated file.

  A resolve!-free run ends in shadow verification: the full history is applied to a
  scratch database and must produce the model's schema. Passing it is what finalizes
  a resolved draft - there is no separate finalization step or marker.
  """

  use Mix.Task

  alias Hologram.Entity.Model
  alias Hologram.Migration.Generator
  alias Hologram.Migration.Loader
  alias Hologram.Reflection
  alias Mix.Tasks.Format

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run(_args) do
    model = Model.from_modules(Reflection.list_entities(), Reflection.list_roles())

    dir = Loader.migrations_dir!()

    opts = [
      dir: dir,
      namespace: default_namespace(),
      format: project_formatter(dir)
    ]

    Loader.list!()
    |> Generator.generate(model, DateTime.utc_now(), opts)
    |> report()
  rescue
    # Exception.message/1 rather than the :message field - Postgrex.Error keeps its detail
    # in :postgres and leaves :message nil, which Mix.raise/1 will not take.
    error in [Hologram.CompileError, Postgrex.Error, RuntimeError] ->
      error
      |> Exception.message()
      |> Mix.raise()
  end

  defp default_namespace do
    app_namespace =
      Reflection.otp_app()
      |> Atom.to_string()
      |> Macro.camelize()

    # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
    Module.concat(app_namespace, "Migrations")
  end

  defp pluralize(1, word), do: "1 #{word}"

  defp pluralize(count, word), do: "#{count} #{word}s"

  defp print(output) do
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(output)
  end

  # The project's own formatter options - its line length among them - so a fresh file is
  # formatted the way mix format, run where this task runs, formats it, and a format check
  # run from the same directory finds nothing to change.
  defp project_formatter(dir) do
    {formatter, _opts} =
      dir
      |> Path.join("migration.ex")
      |> Format.formatter_for_file()

    formatter
  end

  defp report(:nothing_to_do) do
    print("The migration history already produces the model - nothing to generate.")
    print("Verified - migration finalized.")
  end

  defp report({:ok, path, 0}) do
    print("Generated #{path}")
    print("Verified - migration finalized.")
  end

  defp report({:ok, path, question_count}) do
    print("Generated #{path} - #{pluralize(question_count, "question")} to resolve.")
  end

  defp report({:error, {:unresolved, entries}}) do
    lines = Loader.unresolved_lines(entries)

    Mix.raise(
      "the migration draft is not resolved yet:\n#{lines}\n" <>
        "Write the ops that express what happened, delete the resolve! lines, " <>
        "then run this task again."
    )
  end
end
