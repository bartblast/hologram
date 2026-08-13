defmodule Hologram.Migration.Generator do
  @moduledoc false

  @indent "  "

  # Entity-level ops are flat statements even though they name an entity - blocks scope
  # member ops, and these two scope nothing.
  @flat_entity_ops [:delete_entity, :rename_entity]

  @doc """
  Returns the text of the migration file expressing the given plan.

  Entity renames come first, so every later line names the entity as the current model
  does - then the entity blocks in alphabetical order, then the flat ops. The rendered
  text is formatter-stable: the vocabulary is exported as parens-free, so a project's
  mix format leaves generated files alone.
  """
  @spec render(%{atom => any}) :: String.t()
  def render(plan) do
    sections =
      plan.ops
      |> group_ops()
      |> Enum.map(&render_section/1)

    body = Enum.join(sections, "\n\n")

    "use Hologram.Migration\n\n" <> body <> "\n"
  end

  defp block_op?(op) do
    Map.has_key?(op, :entity) and op.op not in @flat_entity_ops
  end

  defp entity_of(op), do: Map.get(op, :entity)

  # Sections in canonical order: renames first (the ordering rule - every later line
  # names the current model's spelling), then the entity blocks, then the flat ops that
  # take no scope.
  defp group_ops(ops) do
    {entity_ops, flat_ops} = Enum.split_with(ops, &block_op?/1)
    {renames, other_flat_ops} = Enum.split_with(flat_ops, &(&1.op == :rename_entity))

    blocks =
      entity_ops
      |> Enum.group_by(&entity_of/1)
      |> Enum.sort_by(fn {entity_type, _ops} -> inspect(entity_type) end)
      |> Enum.map(fn {entity_type, block_ops} -> {:block, entity_type, block_ops} end)

    Enum.map(renames, &{:flat, &1}) ++ blocks ++ Enum.map(other_flat_ops, &{:flat, &1})
  end

  defp render_args(args) do
    Enum.map_join(args, ", ", &inspect/1)
  end

  # An op renders as its verb followed by its arguments, keyword payloads spelled bare -
  # the same statement style the vocabulary macros accept.
  defp render_call(verb, args, opts) do
    rendered_opts = render_opts(opts)
    rendered_args = render_args(args)

    case {rendered_args, rendered_opts} do
      {"", ""} -> "#{verb}"
      {"", _opts} -> "#{verb} #{rendered_opts}"
      {_args, ""} -> "#{verb} #{rendered_args}"
      _both -> "#{verb} #{rendered_args}, #{rendered_opts}"
    end
  end

  defp render_op(%{op: :add_attribute} = op) do
    render_call("add_attribute", [op.name, op.type], op.opts)
  end

  defp render_op(%{op: :add_enum_value} = op) do
    render_call("add_enum_value", [op.attribute, op.value], op.opts)
  end

  defp render_op(%{op: :add_relationship} = op) do
    render_call("add_relationship", [op.name, op.type], op.opts)
  end

  defp render_op(%{op: :add_role, entity: _entity} = op) do
    render_call("add_role", [op.name], op.opts)
  end

  defp render_op(%{op: :add_role, role: role} = op) do
    render_call("add_role", [role], op.opts)
  end

  defp render_op(%{op: :change_attribute} = op) do
    render_call("change_attribute", [op.name], op.changes)
  end

  defp render_op(%{op: :change_relationship} = op) do
    render_call("change_relationship", [op.name], op.changes)
  end

  defp render_op(%{op: :change_role, entity: _entity} = op) do
    render_call("change_role", [op.name], op.changes)
  end

  defp render_op(%{op: :change_role, role: role} = op) do
    render_call("change_role", [role], op.changes)
  end

  defp render_op(%{op: :create_entity} = op) do
    render_call("create_entity", [op.entity], [])
  end

  defp render_op(%{op: :delete_attribute} = op) do
    render_call("delete_attribute", [op.name], [])
  end

  defp render_op(%{op: :delete_entity} = op) do
    render_call("delete_entity", [op.entity], [])
  end

  defp render_op(%{op: :delete_enum_value} = op) do
    render_call("delete_enum_value", [op.attribute, op.value], [])
  end

  defp render_op(%{op: :delete_relationship} = op) do
    render_call("delete_relationship", [op.name], [])
  end

  defp render_op(%{op: :delete_role, entity: _entity} = op) do
    render_call("delete_role", [op.name], [])
  end

  defp render_op(%{op: :delete_role, role: role}) do
    render_call("delete_role", [role], [])
  end

  defp render_op(%{op: :rename_attribute} = op) do
    render_call("rename_attribute", [op.from, op.to], [])
  end

  defp render_op(%{op: :rename_entity} = op) do
    render_call("rename_entity", [op.from, op.to], [])
  end

  defp render_op(%{op: :rename_enum_value} = op) do
    render_call("rename_enum_value", [op.attribute, op.from, op.to], [])
  end

  defp render_op(%{op: :rename_relationship} = op) do
    render_call("rename_relationship", [op.from, op.to], [])
  end

  defp render_op(%{op: :rename_role} = op) do
    render_call("rename_role", [op.from, op.to], [])
  end

  defp render_op(%{op: :reorder_enum_values} = op) do
    render_call("reorder_enum_values", [op.attribute, op.values], [])
  end

  defp render_opts([]), do: ""

  defp render_opts(opts) do
    Enum.map_join(opts, ", ", fn {key, value} -> "#{key}: #{inspect(value)}" end)
  end

  # An entity block whose ops include the creation renders as create_entity - the
  # creation itself is the header, never a member line.
  defp render_section({:block, entity_type, ops}) do
    {creations, member_ops} = Enum.split_with(ops, &(&1.op == :create_entity))
    verb = if creations == [], do: "change_entity", else: "create_entity"
    member_lines = Enum.map_join(member_ops, "\n", &"#{@indent}#{render_op(&1)}")

    "#{verb} #{inspect(entity_type)} do\n#{member_lines}\nend"
  end

  defp render_section({:flat, op}), do: render_op(op)
end
