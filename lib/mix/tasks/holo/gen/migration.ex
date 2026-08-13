defmodule Mix.Tasks.Holo.Gen.Migration do
  @shortdoc "Generates the migration for uncovered model changes"

  @moduledoc """
  Generates the migration expressing the model changes the migration history does not
  cover yet.

      $ mix holo.gen.migration

  The task's behavior follows the state of the migrations directory: nothing to do when
  the history already produces the model, a new file when it does not, and a refusal
  while a draft still holds unanswered questions - those are answered by editing the
  draft, writing the ops that express what happened and deleting the resolve! line.

  A generated file is never amended: when several small files pile up in one branch,
  delete the unmerged ones and run the task again to get a single consolidated file.
  """

  use Mix.Task

  alias Hologram.Entity.Model
  alias Hologram.Migration.Generator
  alias Hologram.Migration.Loader
  alias Hologram.Reflection

  @requirements ["app.config"]

  @doc false
  @impl Mix.Task
  def run(_args) do
    model = Model.from_modules(Reflection.list_entities(), Reflection.list_roles())

    Loader.migrations_dir()
    |> Generator.generate(model, DateTime.utc_now())
    |> report()
  end

  defp pluralize(1, word), do: "1 #{word}"

  defp pluralize(count, word), do: "#{count} #{word}s"

  defp print(output) do
    # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
    IO.puts(output)
  end

  defp report(:nothing_to_do) do
    print("The migration history already produces the model - nothing to generate.")
  end

  defp report({:ok, path, 0}) do
    print("Generated #{path}")
  end

  defp report({:ok, path, question_count}) do
    print("Generated #{path} - #{pluralize(question_count, "question")} to resolve.")
  end

  defp report({:error, {:unresolved, entries}}) do
    lines =
      Enum.map_join(entries, "\n", fn {path, op} ->
        "  #{path}:#{op.line} - #{inspect(op.kind)}"
      end)

    Mix.raise(
      "the migration draft is not resolved yet:\n#{lines}\n" <>
        "Write the ops that express what happened, delete the resolve! lines, " <>
        "then run this task again."
    )
  end
end
