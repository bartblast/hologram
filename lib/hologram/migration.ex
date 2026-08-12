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
          change_entity: 2,
          create_entity: 1,
          create_entity: 2,
          delete_entity: 1,
          question: 1,
          question: 2,
          rename_entity: 2
        ]
    end
  end

  @doc """
  Returns the list of member ops from the given do-block, each op recording a change
  scoped to the given existing entity type.

  Member ops are legal only inside entity blocks - the block injects its entity type
  into each of them.
  """
  defmacro change_entity(entity_type, do: block) do
    block
    |> block_statements()
    |> Enum.map(&member_op(&1, entity_type, __CALLER__))
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
  Returns the op recording that the given entity type came into existence, followed by
  the member ops from the given do-block, each scoped to it.
  """
  defmacro create_entity(entity_type, do: block) do
    line = __CALLER__.line

    create_op =
      quote do
        %{op: :create_entity, entity: unquote(entity_type), line: unquote(line)}
      end

    member_ops =
      block
      |> block_statements()
      |> Enum.map(&member_op(&1, entity_type, __CALLER__))

    [create_op | member_ops]
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

  defp block_statements(nil), do: []

  defp block_statements({:__block__, _meta, statements}), do: statements

  defp block_statements(single_statement), do: [single_statement]

  defp member_op({:add_attribute, meta, [name, type]}, entity_type, caller) do
    member_op({:add_attribute, meta, [name, type, []]}, entity_type, caller)
  end

  defp member_op({:add_attribute, meta, [name, type, opts]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :add_attribute,
        entity: unquote(entity_type),
        name: unquote(name),
        type: unquote(type),
        opts: unquote(opts),
        line: unquote(line)
      }
    end
  end

  defp member_op({:change_attribute, meta, [name, changes]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :change_attribute,
        entity: unquote(entity_type),
        name: unquote(name),
        changes: unquote(changes),
        line: unquote(line)
      }
    end
  end

  defp member_op({:delete_attribute, meta, [name]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :delete_attribute,
        entity: unquote(entity_type),
        name: unquote(name),
        line: unquote(line)
      }
    end
  end

  defp member_op({:question, meta, [kind]}, entity_type, caller) do
    member_op({:question, meta, [kind, []]}, entity_type, caller)
  end

  defp member_op({:question, meta, [kind, payload]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :question,
        entity: unquote(entity_type),
        kind: unquote(kind),
        payload: unquote(payload),
        line: unquote(line)
      }
    end
  end

  defp member_op({:rename_attribute, meta, [old, new]}, entity_type, caller) do
    line = statement_line(meta, caller)

    quote do
      %{
        op: :rename_attribute,
        entity: unquote(entity_type),
        from: unquote(old),
        to: unquote(new),
        line: unquote(line)
      }
    end
  end

  defp member_op({name, meta, args}, _entity_type, caller) when is_atom(name) and is_list(args) do
    raise Hologram.CompileError,
      message:
        "unknown migration op #{name}/#{length(args)} at line #{statement_line(meta, caller)} - " <>
          "see Hologram.Migration for the vocabulary"
  end

  defp member_op(_statement, _entity_type, caller) do
    raise Hologram.CompileError,
      message:
        "invalid statement in a migration entity block starting at line #{caller.line} - " <>
          "entity blocks contain only member ops"
  end

  defp statement_line(meta, caller) do
    Keyword.get(meta, :line, caller.line)
  end
end
