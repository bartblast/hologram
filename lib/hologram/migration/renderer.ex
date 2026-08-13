defmodule Hologram.Migration.Renderer do
  @moduledoc false

  alias Hologram.DB.Mapper
  alias Hologram.DB.Schema
  alias Hologram.Entity.Model

  # Physical ops that reference objects rather than defining them, so they run once
  # everything they name exists - the file-scope form of 02b's phase order.
  @deferred_ops [:add_foreign_key, :create_index]

  @doc """
  Returns the physical ops applying the given logical ops to a database holding the
  given model, plus the model they leave behind.

  The ops are split by how they execute: :transactional runs inside the migration file's
  transaction, :tail after it commits - index builds on tables that already carry rows
  go concurrently, which PostgreSQL forbids inside a transaction.

  The ops render through the mapping: the model before and after them project to physical
  schema terms, and their difference is what the database must do. Physical names
  therefore never enter the migration history - a change to the derived-name rules
  changes what the same history renders to. Rendering the ops together rather than one by
  one keeps the statements minimal: an entity arriving with its attributes is one CREATE
  TABLE, not a table followed by a column at a time.
  """
  @spec render(list(%{atom => any}), %{atom => map}) :: %{atom => any}
  def render(logical_ops, pre_model) do
    post_model = Model.fold(pre_model, logical_ops)

    physical_ops =
      pre_model
      |> term()
      |> Schema.diff(term(post_model))
      |> attach_backfills(logical_ops)

    ordered = order(physical_ops)
    born_here = born_here(ordered)
    {transactional, tail} = Enum.split_with(ordered, &(not concurrent?(&1, born_here)))

    %{
      transactional: transactional,
      tail: Enum.map(tail, &Map.put(&1, :concurrently, true)),
      post_model: post_model
    }
  end

  # A backfill rides its logical op, never the model - the physical column it fills is
  # found by the name the mapper derives for that attribute.
  defp attach_backfills(physical_ops, logical_ops) do
    backfills =
      for %{op: :add_attribute} = op <- logical_ops,
          {:ok, value} <- [Keyword.fetch(op.opts, :backfill)],
          into: %{} do
        {{Mapper.table_name(op.entity), Atom.to_string(op.name)}, value}
      end

    Enum.map(physical_ops, &put_backfill(&1, backfills))
  end

  defp born_here(ops) do
    for %{op: :create_table, table: table} <- ops, into: MapSet.new(), do: table
  end

  # An index on a table born in this file builds inside the transaction - the table is
  # empty, so the build is instant and the file keeps its all-or-nothing shape.
  defp concurrent?(%{op: :create_index} = op, born_here) do
    op.table not in born_here
  end

  defp concurrent?(_op, _born_here), do: false

  # Foreign key drops run first and the referencing ops last, so an op never names an
  # object a later op in the same file creates.
  defp order(ops) do
    {fk_drops, rest} = Enum.split_with(ops, &(&1.op == :drop_foreign_key))
    {deferred, middle} = Enum.split_with(rest, &(&1.op in @deferred_ops))

    fk_drops ++ middle ++ deferred
  end

  defp put_backfill(%{op: :add_column} = op, backfills) do
    case Map.fetch(backfills, {op.table, op.column}) do
      {:ok, value} -> Map.put(op, :backfill, value)
      :error -> op
    end
  end

  defp put_backfill(op, _backfills), do: op

  defp term(model) do
    model
    |> Mapper.derive_from_model!()
    |> Schema.from_mapping()
  end
end
