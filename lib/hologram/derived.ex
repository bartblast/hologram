defmodule Hologram.Derived do
  @moduledoc false

  # What entity and component derived fields share: the forms a definition can take, what its head
  # may name, and how fields reading each other in a cycle are found.

  @doc """
  Returns how the given derived field definition spells the function it captures and that
  function's arity, or nil when the definition is no capture of a named function.
  """
  @spec captured(Macro.t()) :: {String.t(), non_neg_integer} | nil
  def captured({:&, _meta, [{:/, _slash_meta, [target, arity]}]}) when is_integer(arity) do
    case captured_name(target) do
      nil -> nil
      spelled -> {spelled, arity}
    end
  end

  def captured(_definition), do: nil

  @doc """
  Returns the cycles among derived fields, given what each field reads: the fields of each strongly
  connected part with more than one field, and each field reading itself, as one-field lists. A
  field read but not given reads nothing.
  """
  @spec cycles(%{term => [term]}) :: [[term]]
  def cycles(reads) do
    graph = :digraph.new()

    try do
      Enum.each(reads, fn {field, read_fields} ->
        :digraph.add_vertex(graph, field)
        Enum.each(read_fields, &:digraph.add_vertex(graph, &1))
      end)

      Enum.each(reads, fn {field, read_fields} ->
        Enum.each(read_fields, &:digraph.add_edge(graph, field, &1))
      end)

      graph
      |> :digraph_utils.strong_components()
      |> Enum.filter(fn
        [field] -> field in Map.get(reads, field, [])
        _fields -> true
      end)
    after
      :digraph.delete(graph)
    end
  end

  @doc """
  Returns the given derived field definition as the function it stands for.

  A capture of a zero-arity function, local or remote, stands for the function calling it: it reads
  no field, so it hides no input and names no argument, and `&tags_query/0` is
  `fn -> tags_query() end`. Any other definition is returned as given.

  Raises Hologram.CompileError, located at the declaration, on a capture of a function with
  arguments, since the arguments are the fields the value reads and a capture leaves them unwritten.
  """
  @spec function(Macro.t(), Macro.t(), Macro.Env.t()) :: Macro.t()
  def function(name, definition, env)

  def function(
        _name,
        {:&, meta, [{:/, _slash_meta, [{fun_name, fun_meta, context}, 0]}]},
        _env
      )
      when is_atom(fun_name) and is_atom(context) do
    zero_arity_function({fun_name, fun_meta, []}, meta)
  end

  def function(
        _name,
        {:&, meta,
         [{:/, _slash_meta, [{{:., _dot_meta, [_module, _fun_name]}, _call_meta, []} = call, 0]}]},
        _env
      ) do
    zero_arity_function(call, meta)
  end

  def function(name, definition, env) when is_tuple(definition) and elem(definition, 0) == :& do
    case captured(definition) do
      {spelled, arity} -> raise_capture_with_arguments!(name, spelled, arity, env)
      nil -> definition
    end
  end

  def function(_name, definition, _env), do: definition

  @doc """
  Validates the function a derived field is declared with, as written: a function of one clause
  whose arguments are distinct bare names, with no pattern, default or guard - each one names a
  field.

  Returns :ok, or raises Hologram.CompileError located at the declaration.
  """
  @spec validate_function!(Macro.t(), Macro.t(), Macro.Env.t()) :: :ok
  def validate_function!(name, definition, env) do
    field = "derived field #{Macro.to_string(name)} in #{inspect(env.module)}"

    case definition do
      {:fn, _meta, [{:->, _arrow_meta, [[{:when, _when_meta, when_args}], _body]}]} ->
        guard = List.last(when_args)

        declaration_error!(
          "the function of #{field} takes no guard, got: when #{Macro.to_string(guard)} - its arguments name the fields it reads",
          env
        )

      {:fn, _meta, [{:->, _arrow_meta, [args, _body]}]} ->
        validate_args!(field, args, env)

      {:fn, _meta, clauses} ->
        declaration_error!(
          "the function of #{field} has #{length(clauses)} clauses - a derived field's function has one clause, since its head names the fields it reads",
          env
        )

      _definition ->
        declaration_error!(
          "#{field} is defined by a function whose arguments name the fields it reads, got: #{Macro.to_string(definition)} - write it as fn fields -> ... end, calling a shared query builder from the body if one computes it",
          env
        )
    end
  end

  @doc """
  Validates that the given names a derived field's function head binds are fields of the given
  module, given the names of the fields it can read - atoms or strings, since an entity type's field
  names are gathered as strings, the reference fields its relationships imply (`owner_id`)
  included - and that none is the field itself.

  Returns :ok, or raises Hologram.CompileError located at the given file and line.
  """
  @spec validate_head!(module, atom, [atom], [atom | String.t()], {String.t(), pos_integer}) ::
          :ok
  def validate_head!(module, name, arg_names, field_names, {file, line}) do
    field_names = Enum.map(field_names, &to_string/1)

    Enum.each(arg_names, fn arg_name ->
      cond do
        arg_name == name ->
          raise Hologram.CompileError,
            file: file,
            line: line,
            message:
              "derived field #{inspect(name)} in #{inspect(module)} reads itself - a derived field is computed from other fields"

        Atom.to_string(arg_name) not in field_names ->
          raise Hologram.CompileError,
            file: file,
            line: line,
            message: not_a_field_message(module, name, arg_name, field_names)

        true ->
          :ok
      end
    end)
  end

  # A local capture is written as a bare name, a remote one as a call with no arguments. Anything
  # else is no capture of a named function, and is left to the checks of the function form.
  defp captured_name({fun_name, _meta, context}) when is_atom(fun_name) and is_atom(context),
    do: Atom.to_string(fun_name)

  defp captured_name({{:., _dot_meta, [module, fun_name]}, _meta, []}),
    do: "#{Macro.to_string(module)}.#{fun_name}"

  defp captured_name(_target), do: nil

  @spec declaration_error!(String.t(), Macro.Env.t()) :: no_return
  defp declaration_error!(message, env) do
    raise Hologram.CompileError, message: message, file: env.file, line: env.line
  end

  defp not_a_field_message(module, name, arg_name, field_names) do
    readable =
      field_names
      |> List.delete(Atom.to_string(name))
      |> Enum.sort()

    listed =
      if readable == [],
        do: ", and #{inspect(module)} declares none",
        else: ": " <> Enum.join(readable, ", ")

    "#{arg_name} is not a field of #{inspect(module)} - the arguments of derived field #{inspect(name)}'s function name the fields it reads#{listed}"
  end

  @spec raise_capture_with_arguments!(Macro.t(), String.t(), pos_integer, Macro.Env.t()) ::
          no_return
  defp raise_capture_with_arguments!(name, spelled, arity, env) do
    raise Hologram.CompileError,
      message:
        "derived field #{Macro.to_string(name)} in #{inspect(env.module)} is a capture of #{spelled}/#{arity}, " <>
          "which hides the fields it reads - write fn ... -> #{spelled}(...) end, naming them in the head",
      file: env.file,
      line: env.line
  end

  # Each argument names a field, so it is a bare name, written once - a pattern, a default or a
  # guard would make the head say something other than which fields the body reads.
  defp validate_args!(field, args, env) do
    Enum.each(args, fn
      {arg_name, _meta, context}
      when is_atom(arg_name) and is_atom(context) and
             arg_name not in [:_, :__MODULE__, :__ENV__, :__CALLER__, :__DIR__, :__STACKTRACE__] ->
        :ok

      arg ->
        declaration_error!(
          "the arguments of #{field}'s function name fields, each a bare name, got: #{Macro.to_string(arg)} - a pattern, a default or the underscore has no field to name",
          env
        )
    end)

    arg_names = Enum.map(args, fn {arg_name, _meta, _context} -> arg_name end)

    case arg_names -- Enum.uniq(arg_names) do
      [] ->
        :ok

      [repeated_name | _repeated_names] ->
        declaration_error!(
          "#{repeated_name} is named twice in the head of #{field}'s function - each argument names a field once",
          env
        )
    end
  end

  defp zero_arity_function(call, meta) do
    {:fn, meta, [{:->, meta, [[], call]}]}
  end
end
