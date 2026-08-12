defmodule Hologram.Migration do
  @moduledoc """
  The migration file vocabulary.

  A migration file is an Elixir script starting with `use Hologram.Migration`, followed
  by statement-style migration ops, one per line. Evaluating the file produces a plain
  list of op maps: each flat op produces one map, and each entity block produces a list
  of maps that the loader flattens. Every op map carries :op, :line, and the op's payload.
  Entity types are referenced by fully-qualified module name as spelled at that point in
  history - the name stays a valid reference after the module is renamed or deleted.
  """

  defmacro __using__(_opts) do
    quote do
      import Hologram.Migration,
        only: [
          create_entity: 1,
          delete_entity: 1,
          question: 1,
          question: 2,
          rename_entity: 2
        ]
    end
  end

  @doc """
  Returns the op recording that the given entity type came into existence.
  """
  defmacro create_entity(entity_type) do
    line = __CALLER__.line

    quote do
      %{op: :create_entity, entity: unquote(entity_type), line: unquote(line)}
    end
  end

  @doc """
  Returns the op recording that the given entity type was deleted, its table dropped
  with its data.
  """
  defmacro delete_entity(entity_type) do
    line = __CALLER__.line

    quote do
      %{op: :delete_entity, entity: unquote(entity_type), line: unquote(line)}
    end
  end

  @doc """
  Returns the placeholder op marking an unresolved draft question of the given kind,
  with the detected facts as its payload.

  A migration file containing a question op is a draft - verification, the check task,
  and the applier all refuse it until the question line is replaced by the ops that
  express what happened.
  """
  defmacro question(kind, payload \\ []) do
    line = __CALLER__.line

    quote do
      %{op: :question, kind: unquote(kind), payload: unquote(payload), line: unquote(line)}
    end
  end

  @doc """
  Returns the op recording that the first given entity type was renamed to the second,
  its table and every derived physical name following, existing data preserved.
  """
  defmacro rename_entity(old, new) do
    line = __CALLER__.line

    quote do
      %{op: :rename_entity, from: unquote(old), to: unquote(new), line: unquote(line)}
    end
  end
end
