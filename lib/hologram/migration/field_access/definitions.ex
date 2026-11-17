defmodule Hologram.Migration.FieldAccess.Definitions do
  @moduledoc false

  # The definitions a migration module imports in place of Kernel's (see
  # Hologram.Migration.FieldAccess). Credo takes the two macros named def for functions,
  # and asks them for a spec.

  alias Hologram.Migration.FieldAccess

  # credo:disable-for-next-line Credo.Check.Readability.Specs
  defmacro def(call), do: FieldAccess.define(:def, call)

  # credo:disable-for-next-line Credo.Check.Readability.Specs
  defmacro def(call, expr), do: FieldAccess.define(:def, call, expr)

  defmacro defguard(guard), do: FieldAccess.define(:defguard, guard)

  defmacro defguardp(guard), do: FieldAccess.define(:defguardp, guard)

  defmacro defp(call), do: FieldAccess.define(:defp, call)

  defmacro defp(call, expr), do: FieldAccess.define(:defp, call, expr)

  defmacro defmacro(call), do: FieldAccess.define(:defmacro, call)

  defmacro defmacro(call, expr), do: FieldAccess.define(:defmacro, call, expr)

  defmacro defmacrop(call), do: FieldAccess.define(:defmacrop, call)

  defmacro defmacrop(call, expr), do: FieldAccess.define(:defmacrop, call, expr)

  # The field of an unquote fragment's value, x.field in unquote(x).field: a remote call
  # when the value is a module name, which the call check judges, and a strict map read
  # otherwise.
  defmacro __field__(receiver, field) do
    if is_atom(receiver) or match?({:__aliases__, _meta, _parts}, receiver) or
         match?({:__MODULE__, _meta, context} when is_atom(context), receiver),
       do: {{:., [], [receiver, field]}, [no_parens: true], []},
       else: quote(do: :erlang.map_get(unquote(field), unquote(receiver)))
  end
end
