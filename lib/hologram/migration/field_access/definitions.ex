defmodule Hologram.Migration.FieldAccess.Definitions do
  @moduledoc false

  # The definitions a migration module imports in place of Kernel's (see
  # Hologram.Migration.FieldAccess). Credo takes the two macros named def for functions,
  # and asks them for a spec.

  alias Hologram.Migration.FieldAccess

  @guards_attribute :__hologram_migration_guards__

  # credo:disable-for-next-line Credo.Check.Readability.Specs
  defmacro def(call), do: FieldAccess.define(:def, call)

  # credo:disable-for-next-line Credo.Check.Readability.Specs
  defmacro def(call, expr), do: FieldAccess.define(:def, call, expr)

  defmacro defguard(guard), do: define_guard(:defguard, guard)

  defmacro defguardp(guard), do: define_guard(:defguardp, guard)

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

  @doc """
  Registers the attribute the given module records the guards it defines in.
  """
  @spec register_guards(module) :: :ok
  def register_guards(module) do
    Module.register_attribute(module, @guards_attribute, accumulate: true)
  end

  @doc """
  Whether the given macro of the given module is a guard it defines, still in the one clause the
  guard defined. A guard's code is expanded where the guard is defined, so it reads the module
  there, unlike another macro's. Takes a module still being compiled.
  """
  @spec guard?(module, {atom, non_neg_integer}) :: boolean
  def guard?(module, call) do
    definition = Module.get_definition(module, call)

    match?({:v1, _kind, _meta, [_clause]}, definition) and
      {call, definition} in Module.get_attribute(module, @guards_attribute)
  end

  # The guard is recorded with its definition where the module body runs, as it's defined, so one
  # in a branch that doesn't run, or one a macro has since replaced, can't vouch for another macro
  # of its name. A guard made overridable counts as replaced, and one whose name is unquoted isn't
  # recorded: both are refused like any other macro.
  defp define_guard(kind, guard) do
    case guard_call(guard) do
      nil ->
        FieldAccess.define(kind, guard)

      call ->
        quote do
          unquote(FieldAccess.define(kind, guard))

          Module.put_attribute(
            __MODULE__,
            unquote(@guards_attribute),
            {unquote(call), Module.get_definition(__MODULE__, unquote(call))}
          )
        end
    end
  end

  defp guard_call({:when, _meta, [{name, _call_meta, args}, _body]})
       when is_atom(name) and is_list(args),
       do: {name, length(args)}

  defp guard_call({:when, _meta, [{name, _call_meta, context}, _body]})
       when is_atom(name) and is_atom(context),
       do: {name, 0}

  defp guard_call(_guard), do: nil
end
