defmodule Hologram.Migration.FieldAccess do
  @moduledoc false

  alias Hologram.Migration.FieldAccess.Definitions
  alias Hologram.Migration.Value

  # Elixir compiles x.field into a map read that, when x holds a module rather than a map,
  # calls that module's zero-arity function instead - the build cannot tell which, as both
  # compile alike. A migration's def, defp, defmacro, defmacrop, defguard and defguardp (see
  # Hologram.Migration.FieldAccess.Definitions) and its ops rewrite every field access on a
  # value that is not a module name into :erlang.map_get/2: a map or struct reads as before,
  # a missing key raises KeyError as before, and a module raises BadMapError rather than
  # being called. A quote's code is data, and stays as written, as does what a call to the
  # migration's own macro takes: the macro's result is rewritten where it expands.

  # The macro arities, whose first argument is a path they take apart into Map calls,
  # which raise BadMapError on a module themselves - a field access left in it is part of
  # the path. Their function arities take a plain value.
  @path_macros [get_and_update_in: 2, get_in: 1, pop_in: 1, put_in: 2, update_in: 2]

  @doc """
  Returns the quoted definition of the given kind - :def, :defp, :defmacro, :defmacrop,
  :defguard or :defguardp - with field access rewritten in its head and body (see
  `rewrite/3`), the given env being where it's written. Its guards, default arguments and
  body are rewritten where Elixir expands them, once its unquote fragments are in and the
  macros the module defined before it are known. A macro's quotes are data like any other,
  so it rewrites the code it returns too, where it expands.
  """
  @spec define(atom, Macro.Env.t(), Macro.t(), Macro.t() | nil) :: Macro.t()
  def define(kind, env, call, expr \\ nil)

  def define(kind, env, call, nil) do
    quote do
      Kernel.unquote(kind)(unquote(head(call, env)))
    end
  end

  def define(kind, env, call, expr) when kind in [:defmacro, :defmacrop] do
    quote do
      Kernel.unquote(kind)(unquote(head(call, env)), unquote(body(expr, env, &code_call/1)))
    end
  end

  def define(kind, env, call, expr) do
    quote do
      Kernel.unquote(kind)(unquote(head(call, env)), unquote(body(expr, env, &body_call/1)))
    end
  end

  @doc """
  Returns the given quoted code with every field access on a value that is not a module
  name rewritten into a strict map read, the given env being where the code expands. A
  quote's code is data, so only the code it runs is rewritten (see
  `Hologram.Migration.Value.map_reduce_quote/5`), and the given splicing says whether the
  function the code is written in splices in an unquote outside a quote, as def does.

  Raises Hologram.CompileError on a field access in code a quote runs only when its
  options, which only the compiler can read, say so.
  """
  @spec rewrite(Macro.t(), Macro.Env.t(), Value.splicing()) :: Macro.t()
  def rewrite(ast, env, splicing \\ true)

  def rewrite({:quote, _meta, args} = node, env, splicing) when is_list(args),
    do: rewrite_quote(node, env, splicing)

  # A quote a pipe goes into can be bare, with no parentheses.
  def rewrite({:|>, meta, [_left, {:quote, _quote_meta, args}]} = node, env, splicing)
      when is_list(args) or is_atom(args) do
    if own_macro?(env, meta, :|>, 2), do: node, else: rewrite_quote(node, env, splicing)
  end

  def rewrite(
        {{:., _dot_meta, [_receiver, :|>]}, _meta, [_left, {:quote, _quote_meta, args}]} = node,
        env,
        splicing
      )
      when is_list(args) or is_atom(args),
      do: rewrite_quote(node, env, splicing)

  # A field of an unquote fragment's value is decided once the value is unquoted.
  def rewrite(
        {{:., _dot_meta, [{:unquote, _unquote_meta, [_value]} = receiver, field]}, meta, []},
        _env,
        _splicing
      )
      when is_atom(field) do
    if meta[:no_parens] == true,
      do:
        {{:., [], [Definitions, :__field__]}, Keyword.delete(meta, :no_parens), [receiver, field]},
      else: {{:., [], [receiver, field]}, meta, []}
  end

  def rewrite({{:., dot_meta, [receiver, field]}, meta, []}, env, splicing) do
    if meta[:no_parens] == true and is_atom(field) and not module_name?(receiver) do
      {{:., dot_meta, [:erlang, :map_get]}, Keyword.delete(meta, :no_parens),
       [field, rewrite(receiver, env, splicing)]}
    else
      {{:., dot_meta, [rewrite(receiver, env, splicing), field]}, meta, []}
    end
  end

  # In an unquote fragment, row.unquote(name)() calls the function the fragment names, and
  # row.unquote(name) reads the field it names.
  def rewrite(
        {{{:., dot_meta, [receiver, :unquote]}, call_meta, [name]}, meta, []},
        env,
        splicing
      ) do
    {{{:., dot_meta, [rewrite(receiver, env, splicing), :unquote]}, call_meta,
      [rewrite(name, env, false)]}, meta, []}
  end

  def rewrite({{:., dot_meta, [receiver, :unquote]}, meta, [name]} = ast, env, splicing) do
    if module_name?(receiver),
      do: rewrite_args(ast, env, splicing),
      else:
        {{:., dot_meta, [:erlang, :map_get]}, meta,
         [{:unquote, meta, [rewrite(name, env, false)]}, rewrite(receiver, env, splicing)]}
  end

  # An unquote fragment's value runs on its own, where nothing splices.
  def rewrite({form, meta, [value]}, env, _splicing)
      when form in [:unquote, :unquote_splicing] do
    {form, meta, [rewrite(value, env, false)]}
  end

  # A capture, &x.fun/1, names the function rather than reading a field - unless the
  # receiver holds a placeholder, as in &(&1.total / 2), which divides a field.
  def rewrite(
        {:&, _meta,
         [{:/, _slash_meta, [{{:., _dot_meta, [receiver, fun]}, _call_meta, []}, arity]}]} =
          capture,
        env,
        splicing
      )
      when is_atom(fun) and is_integer(arity) do
    if placeholder?(receiver), do: rewrite_args(capture, env, splicing), else: capture
  end

  # A pipe passes the first argument, so a path macro at its end takes the left side as
  # its path, and the migration's own macro takes it as written.
  def rewrite({:|>, meta, [_left, _right]} = ast, env, splicing) do
    if own_macro?(env, meta, :|>, 2), do: ast, else: rewrite_kernel_pipe(ast, env, splicing)
  end

  def rewrite({{:., _dot_meta, [receiver, :|>]}, _meta, [_left, _right]} = ast, env, splicing) do
    if kernel?(receiver, env),
      do: rewrite_kernel_pipe(ast, env, splicing),
      else: rewrite_args(ast, env, splicing)
  end

  def rewrite({name, meta, [path | args]} = ast, env, splicing)
      when is_atom(name) and is_list(meta) do
    cond do
      own_macro?(env, meta, name, length(args) + 1) ->
        ast

      {name, length(args) + 1} in @path_macros ->
        {name, meta, [rewrite_path(path, env, splicing) | rewrite(args, env, splicing)]}

      true ->
        rewrite_args(ast, env, splicing)
    end
  end

  def rewrite(
        {{:., _dot_meta, [receiver, name]} = form, meta, [path | args]} = ast,
        env,
        splicing
      )
      when is_atom(name) do
    if {name, length(args) + 1} in @path_macros and kernel?(receiver, env),
      do: {form, meta, [rewrite_path(path, env, splicing) | rewrite(args, env, splicing)]},
      else: rewrite_args(ast, env, splicing)
  end

  def rewrite({_form, _meta, args} = ast, env, splicing) when is_list(args),
    do: rewrite_args(ast, env, splicing)

  def rewrite({left, right}, env, splicing),
    do: {rewrite(left, env, splicing), rewrite(right, env, splicing)}

  def rewrite(list, env, splicing) when is_list(list),
    do: Enum.map(list, &rewrite(&1, env, splicing))

  def rewrite(other, _env, _splicing), do: other

  @doc """
  Returns whether the given receiver of a remote call is Kernel, written with or without the
  Elixir prefix, or as an alias the given env holds for it. Only a module name is expanded, since
  expanding any other code runs its macros, which can raise on code that never runs.
  """
  @spec kernel?(Macro.t(), Macro.Env.t()) :: boolean
  def kernel?(Kernel, _env), do: true

  def kernel?({:__aliases__, _meta, parts} = receiver, env) do
    Enum.all?(parts, &is_atom/1) and Macro.expand(receiver, env) == Kernel
  end

  def kernel?(_receiver, _env), do: false

  # The body as Elixir expands it, after a rescue, catch or after the body takes, wrapped in
  # the given call. An unquote fragment's value is a keyword list only once the definition
  # runs, so the body is taken apart there.
  defp body(expr, env, wrap) do
    if Keyword.keyword?(expr) do
      code = Definitions.__unwrap_body__(expr, env.file, env.line)

      [do: wrap.(code)]
    else
      unwrapped =
        quote do
          Definitions.__unwrap_body__(
            unquote(Macro.escape(expr, unquote: true)),
            unquote(env.file),
            unquote(env.line)
          )
        end

      [do: wrap.({:unquote, [], [unwrapped]})]
    end
  end

  defp body_call(body) do
    quote do
      Definitions.__body__(unquote(body))
    end
  end

  # A macro returns the code it expands to, rewritten where it expands.
  defp code_call(body) do
    quote do
      unquote(body)
      |> Definitions.__body__()
      |> Definitions.__code__(__CALLER__)
    end
  end

  # The first line the code carries.
  defp code_line(code) do
    {_code, line} =
      Macro.prewalk(code, nil, fn
        {_form, meta, _args} = node, nil when is_list(meta) -> {node, meta[:line]}
        node, line -> {node, line}
      end)

    line
  end

  # A head's guards and default arguments may call the module's own macros, so they're
  # rewritten where Elixir expands them, like a body.
  defp head({:when, meta, [call, guards]}, env),
    do: {:when, meta, [head(call, env), head_guards(guards)]}

  defp head({name, meta, args}, env) when is_list(args),
    do: {rewrite(name, env), meta, Enum.map(args, &head_arg(&1, env))}

  defp head(call, env), do: rewrite(call, env)

  defp head_arg({:\\, meta, [pattern, default]}, env),
    do: {:\\, meta, [rewrite(pattern, env), body_call(default)]}

  defp head_arg(pattern, env), do: rewrite(pattern, env)

  defp head_guards({:when, meta, [guard, guards]}),
    do: {:when, meta, [body_call(guard), head_guards(guards)]}

  defp head_guards(guard), do: body_call(guard)

  # Alias.fun, :module.fun and __MODULE__.fun without parentheses are remote calls, which
  # the call check judges by the module they name.
  defp module_name?({:__aliases__, _meta, _parts}), do: true

  defp module_name?({:__MODULE__, _meta, context}) when is_atom(context), do: true

  defp module_name?(receiver), do: is_atom(receiver)

  # A migration's own macro rewrites the code it expands to (see define/4), and the code
  # it takes may be data it returns, so a call to it stays as written. A guard expands to
  # code it doesn't rewrite, so its arguments are rewritten like a function's. A quote's call
  # names the import it was written with, which Elixir takes over the module's own macro.
  defp own_macro?(%Macro.Env{module: module}, meta, name, arity) do
    call = {name, arity}

    not quoted_import?(meta, arity) and module != nil and Module.open?(module) and
      (Module.defines?(module, call, :defmacro) or Module.defines?(module, call, :defmacrop)) and
      not Definitions.guard?(module, call)
  end

  defp quoted_import?(meta, arity) do
    Keyword.has_key?(meta, :context) and List.keymember?(meta[:imports] || [], arity, 0)
  end

  defp placeholder?(ast) do
    {_ast, found?} =
      Macro.prewalk(ast, false, fn
        {:&, _meta, [index]} = node, _found? when is_integer(index) -> {node, true}
        node, found? -> {node, found?}
      end)

    found?
  end

  defp rewrite_args({form, meta, args}, env, splicing),
    do: {rewrite(form, env, splicing), meta, rewrite(args, env, splicing)}

  # A pipe on the right side is the stages after the left side, the first of which takes it. So is
  # Kernel's pipe given only a stage, which passes the left side on to it. Either is rewritten as
  # regrouped, which can be a pipe into a quote.
  defp rewrite_kernel_pipe({form, meta, [left, right]} = pipe, env, splicing) do
    case Value.regroup_pipe(pipe, env) do
      ^pipe -> {form, meta, rewrite_pipe(left, right, env, splicing)}
      regrouped -> rewrite(regrouped, env, splicing)
    end
  end

  # The left side and the call a pipe passes it to, which takes no parentheses when it takes
  # nothing else.
  defp rewrite_pipe(left, {name, meta, args} = right, env, splicing)
       when is_atom(name) and (is_list(args) or is_atom(args)) do
    arity = if is_list(args), do: length(args) + 1, else: 1

    cond do
      own_macro?(env, meta, name, arity) ->
        [left, right]

      {name, arity} in @path_macros ->
        [rewrite_path(left, env, splicing), {name, meta, rewrite(args, env, splicing)}]

      true ->
        [rewrite(left, env, splicing), {name, meta, rewrite(args, env, splicing)}]
    end
  end

  defp rewrite_pipe(
         left,
         {{:., _dot_meta, [receiver, name]} = form, meta, args} = right,
         env,
         splicing
       )
       when is_atom(name) and is_list(args) do
    cond do
      not kernel?(receiver, env) ->
        [rewrite(left, env, splicing), rewrite(right, env, splicing)]

      {name, length(args) + 1} in @path_macros ->
        [rewrite_path(left, env, splicing), {form, meta, rewrite(args, env, splicing)}]

      true ->
        [rewrite(left, env, splicing), {form, meta, rewrite(args, env, splicing)}]
    end
  end

  defp rewrite_pipe(left, right, env, splicing),
    do: [rewrite(left, env, splicing), rewrite(right, env, splicing)]

  # The dots and brackets of a path stay as the macro reads them; the keys in its brackets
  # and the value at its root are rewritten.
  defp rewrite_path({{:., dot_meta, [receiver, field]}, meta, []}, env, splicing)
       when is_atom(field) do
    {{:., dot_meta, [rewrite_path(receiver, env, splicing), field]}, meta, []}
  end

  defp rewrite_path(
         {{:., _dot_meta, [Access, :get]} = form, meta, [receiver, key]},
         env,
         splicing
       ) do
    {form, meta, [rewrite_path(receiver, env, splicing), rewrite(key, env, splicing)]}
  end

  defp rewrite_path(root, env, splicing), do: rewrite(root, env, splicing)

  # A pipe that doesn't expand to a quote is a call like any other.
  defp rewrite_quote(node, env, splicing) do
    rewrite_code = &rewrite_quote_code(&1, &2, &3, &4, env)

    case Value.map_reduce_quote(node, env, splicing, nil, rewrite_code) do
      {:ok, node, nil} -> node
      :error -> rewrite_args(node, env, splicing)
    end
  end

  # Code a quote may run, under options only the compiler can read, would be data when it
  # doesn't, so a field access in it can't be rewritten either way.
  defp rewrite_quote_code(code, nil, true, splicing, env), do: {rewrite(code, env, splicing), nil}

  defp rewrite_quote_code(code, nil, :unknown, splicing, env) do
    if rewrite(code, env, splicing) != code do
      raise Hologram.CompileError,
        message:
          "a migration can't read a field in an unquote of a quote whose options only the " <>
            "compiler can read, like an attribute - write the options out, or read the field " <>
            "with Map.fetch!/2",
        file: env.file,
        line: code_line(code) || env.line
    end

    {code, nil}
  end
end
