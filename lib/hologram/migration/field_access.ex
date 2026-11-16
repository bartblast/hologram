defmodule Hologram.Migration.FieldAccess do
  @moduledoc false

  alias Hologram.Migration.FieldAccess.Definitions

  # Elixir compiles x.field into a map read that, when x holds a module rather than a map,
  # calls that module's zero-arity function instead - the build cannot tell which, as both
  # compile alike. A migration's def, defp, defmacro, defmacrop, defguard and defguardp (see
  # Hologram.Migration.FieldAccess.Definitions) and its ops rewrite every field access on a
  # value that is not a module name into :erlang.map_get/2: a map or struct reads as before,
  # a missing key raises KeyError as before, and a module raises BadMapError rather than
  # being called.

  # The macro arities, whose first argument is a path they take apart into Map calls,
  # which raise BadMapError on a module themselves - a field access left in it is part of
  # the path. Their function arities take a plain value.
  @path_macros [get_and_update_in: 2, get_in: 1, pop_in: 1, put_in: 2, update_in: 2]

  # Kernel as written, or as an op's arguments hold it, its alias expanded.
  defguardp is_kernel(ast)
            when ast == Kernel or
                   (is_tuple(ast) and tuple_size(ast) == 3 and elem(ast, 0) == :__aliases__ and
                      elem(ast, 2) == [:Kernel])

  @doc """
  Returns the quoted definition of the given kind - :def, :defp, :defmacro, :defmacrop,
  :defguard or :defguardp - with field access rewritten in its head and body (see
  `rewrite/1`).
  """
  @spec define(atom, Macro.t(), Macro.t() | nil) :: Macro.t()
  def define(kind, call, expr \\ nil)

  def define(kind, call, nil) do
    quote do
      Kernel.unquote(kind)(unquote(rewrite(call)))
    end
  end

  def define(kind, call, expr) do
    quote do
      Kernel.unquote(kind)(unquote(rewrite(call)), unquote(rewrite(expr)))
    end
  end

  @doc """
  Returns the given quoted code with every field access on a value that is not a module
  name rewritten into a strict map read.
  """
  @spec rewrite(Macro.t()) :: Macro.t()
  # A field of an unquote fragment's value is decided once the value is unquoted.
  def rewrite(
        {{:., _dot_meta, [{:unquote, _unquote_meta, [_value]} = receiver, field]}, meta, []}
      )
      when is_atom(field) do
    if meta[:no_parens] == true,
      do:
        {{:., [], [Definitions, :__field__]}, Keyword.delete(meta, :no_parens), [receiver, field]},
      else: {{:., [], [receiver, field]}, meta, []}
  end

  def rewrite({{:., dot_meta, [receiver, field]}, meta, []}) do
    if meta[:no_parens] == true and is_atom(field) and not module_name?(receiver) do
      {{:., dot_meta, [:erlang, :map_get]}, Keyword.delete(meta, :no_parens),
       [field, rewrite(receiver)]}
    else
      {{:., dot_meta, [rewrite(receiver), field]}, meta, []}
    end
  end

  # In an unquote fragment, row.unquote(name)() calls the function the fragment names, and
  # row.unquote(name) reads the field it names.
  def rewrite({{{:., dot_meta, [receiver, :unquote]}, call_meta, [name]}, meta, []}) do
    {{{:., dot_meta, [rewrite(receiver), :unquote]}, call_meta, [rewrite(name)]}, meta, []}
  end

  def rewrite({{:., dot_meta, [receiver, :unquote]}, meta, [name]} = ast) do
    if module_name?(receiver),
      do: rewrite_args(ast),
      else:
        {{:., dot_meta, [:erlang, :map_get]}, meta, [{:unquote, meta, [name]}, rewrite(receiver)]}
  end

  # A capture, &x.fun/1, names the function rather than reading a field - unless the
  # receiver holds a placeholder, as in &(&1.total / 2), which divides a field.
  def rewrite(
        {:&, _meta,
         [{:/, _slash_meta, [{{:., _dot_meta, [receiver, fun]}, _call_meta, []}, arity]}]} =
          capture
      )
      when is_atom(fun) and is_integer(arity) do
    if placeholder?(receiver), do: rewrite_args(capture), else: capture
  end

  # A pipe passes the first argument, so a path macro at its end takes the left side as
  # its path.
  def rewrite({:|>, meta, [left, {name, call_meta, args}]})
      when is_atom(name) and is_list(args) do
    if {name, length(args) + 1} in @path_macros,
      do: {:|>, meta, [rewrite_path(left), {name, call_meta, rewrite(args)}]},
      else: {:|>, meta, [rewrite(left), {name, call_meta, rewrite(args)}]}
  end

  def rewrite(
        {:|>, meta,
         [
           left,
           {{:., _dot_meta, [kernel, name]} = form, call_meta, args}
         ]}
      )
      when is_kernel(kernel) and is_atom(name) and is_list(args) do
    if {name, length(args) + 1} in @path_macros,
      do: {:|>, meta, [rewrite_path(left), {form, call_meta, rewrite(args)}]},
      else: {:|>, meta, [rewrite(left), {form, call_meta, rewrite(args)}]}
  end

  def rewrite({name, meta, [path | args]} = ast) when is_atom(name) and is_list(meta) do
    if {name, length(args) + 1} in @path_macros,
      do: {name, meta, [rewrite_path(path) | rewrite(args)]},
      else: rewrite_args(ast)
  end

  def rewrite({{:., _dot_meta, [kernel, name]} = form, meta, [path | args]} = ast)
      when is_kernel(kernel) and is_atom(name) do
    if {name, length(args) + 1} in @path_macros,
      do: {form, meta, [rewrite_path(path) | rewrite(args)]},
      else: rewrite_args(ast)
  end

  def rewrite({_form, _meta, args} = ast) when is_list(args), do: rewrite_args(ast)

  def rewrite({left, right}), do: {rewrite(left), rewrite(right)}

  def rewrite(list) when is_list(list), do: Enum.map(list, &rewrite/1)

  def rewrite(other), do: other

  # Alias.fun, :module.fun and __MODULE__.fun without parentheses are remote calls, which
  # the call check judges by the module they name.
  defp module_name?({:__aliases__, _meta, _parts}), do: true

  defp module_name?({:__MODULE__, _meta, context}) when is_atom(context), do: true

  defp module_name?(receiver), do: is_atom(receiver)

  defp placeholder?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:&, _meta, [index]} = node, _found? when is_integer(index) -> {node, true}
        node, found? -> {node, found?}
      end)

    found?
  end

  defp rewrite_args({form, meta, args}), do: {rewrite(form), meta, rewrite(args)}

  # The dots and brackets of a path stay as the macro reads them; the keys in its brackets
  # and the value at its root are rewritten.
  defp rewrite_path({{:., dot_meta, [receiver, field]}, meta, []}) when is_atom(field) do
    {{:., dot_meta, [rewrite_path(receiver), field]}, meta, []}
  end

  defp rewrite_path({{:., _dot_meta, [Access, :get]} = form, meta, [receiver, key]}) do
    {form, meta, [rewrite_path(receiver), rewrite(key)]}
  end

  defp rewrite_path(root), do: rewrite(root)
end
