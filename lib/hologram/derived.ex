defmodule Hologram.Derived do
  @moduledoc false

  # What entity and component derived fields share as written: the forms a definition can take.

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

  def function(name, {:&, _meta, [{:/, _slash_meta, [target, arity]}]} = definition, env)
      when is_integer(arity) do
    case captured_name(target) do
      nil -> definition
      spelled -> raise_capture_with_arguments!(name, spelled, arity, env)
    end
  end

  def function(_name, definition, _env), do: definition

  # A local capture is written as a bare name, a remote one as a call with no arguments. Anything
  # else is no capture of a named function, and is left to the checks of the function form.
  defp captured_name({fun_name, _meta, context}) when is_atom(fun_name) and is_atom(context),
    do: Atom.to_string(fun_name)

  defp captured_name({{:., _dot_meta, [module, fun_name]}, _meta, []}),
    do: "#{Macro.to_string(module)}.#{fun_name}"

  defp captured_name(_target), do: nil

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

  defp zero_arity_function(call, meta) do
    {:fn, meta, [{:->, meta, [[], call]}]}
  end
end
