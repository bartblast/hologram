defmodule Hologram.Migration.FieldAccess.Definitions do
  @moduledoc false

  # The definitions a migration module imports in place of Kernel's (see
  # Hologram.Migration.FieldAccess). Credo takes the two macros named def for functions,
  # and asks them for a spec.

  alias Hologram.Migration.FieldAccess

  @guards_attribute :__hologram_migration_guards__

  @guard_heads_attribute :__hologram_migration_guard_heads__

  # credo:disable-for-next-line Credo.Check.Readability.Specs
  defmacro def(call), do: FieldAccess.define(:def, __CALLER__, call)

  # credo:disable-for-next-line Credo.Check.Readability.Specs
  defmacro def(call, expr), do: FieldAccess.define(:def, __CALLER__, call, expr)

  defmacro defguard(guard), do: define_guard(:defguard, guard, __CALLER__)

  defmacro defguardp(guard), do: define_guard(:defguardp, guard, __CALLER__)

  defmacro defp(call), do: FieldAccess.define(:defp, __CALLER__, call)

  defmacro defp(call, expr), do: FieldAccess.define(:defp, __CALLER__, call, expr)

  defmacro defmacro(call), do: FieldAccess.define(:defmacro, __CALLER__, call)

  defmacro defmacro(call, expr), do: FieldAccess.define(:defmacro, __CALLER__, call, expr)

  defmacro defmacrop(call), do: FieldAccess.define(:defmacrop, __CALLER__, call)

  defmacro defmacrop(call, expr), do: FieldAccess.define(:defmacrop, __CALLER__, call, expr)

  # A function's or macro's body, rewritten where Elixir expands it (see
  # Hologram.Migration.FieldAccess.define/4), where the unquote fragments are in and
  # nothing splices.
  defmacro __body__(body), do: FieldAccess.rewrite(body, __CALLER__, false)

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
  Returns the given code a migration's macro expands to, with field access rewritten (see
  `Hologram.Migration.FieldAccess.rewrite/3`), the given env being where it expands. The code
  replaces the macro's call, where nothing splices it.
  """
  @spec __code__(Macro.t(), Macro.Env.t()) :: Macro.t()
  def __code__(code, env), do: FieldAccess.rewrite(code, env, false)

  @doc """
  Returns the code of the given body of a definition written at the given file and line, the
  keyword list a def takes: its do, or a try of it when it has a rescue, catch, else or after.

  Raises Hologram.CompileError when the body isn't a keyword list, or is an empty one.
  """
  @spec __unwrap_body__(any, String.t(), non_neg_integer) :: Macro.t()
  def __unwrap_body__(expr, file, line) do
    cond do
      not Keyword.keyword?(expr) or expr == [] ->
        raise Hologram.CompileError,
          message:
            "a migration's def, defp, defmacro and defmacrop take their body as do: or a do block",
          file: file,
          line: line

      Keyword.keys(expr) == [:do] ->
        expr[:do]

      true ->
        {:try, [], [expr]}
    end
  end

  @doc """
  Registers the attributes the given module records the guards it defines in, and the defaults
  their heads declare.
  """
  @spec register_guards(module) :: :ok
  def register_guards(module) do
    Module.register_attribute(module, @guards_attribute, accumulate: true)
    Module.register_attribute(module, @guard_heads_attribute, accumulate: true)
  end

  @doc """
  Whether the given macro of the given module is a guard it defines, still in the one clause the
  guard defined. A guard's code is expanded where the guard is defined, so it reads the module
  there, unlike another macro's. Takes a module still being compiled.
  """
  @spec guard?(module, {atom, non_neg_integer}) :: boolean
  def guard?(module, call) do
    module
    |> Module.get_attribute(@guards_attribute, [])
    |> Enum.any?(
      &(List.keymember?(&1, call, 0) and Enum.all?(&1, fn record -> kept?(module, record) end))
    )
  end

  # The guard is recorded with its definitions where the module body runs, as it's defined, so one
  # in a branch that doesn't run, or one a macro has since replaced, can't vouch for another macro
  # of its name. A guard made overridable counts as replaced, and one whose name is unquoted isn't
  # recorded: both are refused like any other macro. The arities its defaults give are recorded
  # together, as a shorter one calls the full one, so replacing any of them refuses them all. A
  # head declaring the defaults apart defines the shorter ones, which the clause after it records:
  # the head is recorded with the definition it leaves, so a clause after another one, or after
  # the definition was deleted, takes none of them.
  defp define_guard(kind, {name, _meta, args} = head, env)
       when is_atom(name) and name != :when and is_list(args) do
    call = {name, length(args)}

    quote do
      unquote(FieldAccess.define(kind, env, head))

      Module.put_attribute(
        __MODULE__,
        unquote(@guard_heads_attribute),
        {unquote(call), Module.get_definition(__MODULE__, unquote(call)),
         unquote(default_calls(name, args))}
      )
    end
  end

  defp define_guard(kind, guard, env) do
    case guard_calls(guard) do
      [] ->
        FieldAccess.define(kind, env, guard)

      [call | _default_calls] = calls ->
        quote do
          head_calls = unquote(__MODULE__).__head_defaults__(__MODULE__, unquote(call))

          unquote(FieldAccess.define(kind, env, guard))

          Module.put_attribute(
            __MODULE__,
            unquote(@guards_attribute),
            for record_call <- unquote(calls) ++ head_calls do
              {record_call, Module.get_definition(__MODULE__, record_call)}
            end
          )
        end
    end
  end

  @doc false
  @spec __head_defaults__(module, {atom, non_neg_integer}) :: list({atom, non_neg_integer})
  def __head_defaults__(module, call) do
    definition = Module.get_definition(module, call)

    for {^call, ^definition, calls} <- Module.get_attribute(module, @guard_heads_attribute, []),
        default_call <- calls,
        do: default_call
  end

  defp kept?(module, {call, definition}) do
    match?({:v1, _kind, _meta, [_clause]}, definition) and
      Module.get_definition(module, call) == definition
  end

  defp guard_calls({:when, _meta, [{name, _call_meta, args}, _body]})
       when is_atom(name) and is_list(args) do
    [{name, length(args)} | default_calls(name, args)]
  end

  defp guard_calls({:when, _meta, [{name, _call_meta, context}, _body]})
       when is_atom(name) and is_atom(context),
       do: [{name, 0}]

  defp guard_calls(_guard), do: []

  # The shorter arities the given args' defaults give.
  defp default_calls(name, args) do
    defaults = Enum.count(args, &match?({:\\, _default_meta, [_arg, _default]}, &1))

    for arity <- (length(args) - defaults)..(length(args) - 1)//1, do: {name, arity}
  end
end
