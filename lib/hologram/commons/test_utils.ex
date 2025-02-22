defmodule Hologram.Commons.TestUtils do
  @moduledoc false

  alias Hologram.Commons.IntegerUtils
  alias Hologram.Commons.KernelUtils
  alias Hologram.Reflection

  defdelegate pid(str), to: IEx.Helpers
  defdelegate port(str), to: IEx.Helpers
  defdelegate ref(str), to: IEx.Helpers

  @doc """
  Builds an error message for ArgumentError.
  """
  @spec build_argument_error_msg(integer(), String.t()) :: String.t()
  def build_argument_error_msg(arg_idx, blame) do
    """
    errors were found at the given arguments:

      * #{IntegerUtils.ordinal(arg_idx)} argument: #{blame}
    """
  end

  @doc """
  Builds an error message for FunctionClauseError.
  """
  @spec build_function_clause_error_msg(String.t(), list, list) :: String.t()
  def build_function_clause_error_msg(fun_name, args \\ [], attempted_clauses \\ []) do
    args_info =
      if Enum.any?(args) do
        initial_acc = "\n\nThe following arguments were given to #{fun_name}:\n"

        args
        |> Enum.with_index()
        |> Enum.reduce(initial_acc, fn {arg, idx}, acc ->
          """
          #{acc}
              # #{idx + 1}
              #{KernelUtils.inspect(arg)}
          """
        end)
      else
        ""
      end

    attempted_clauses_count = Enum.count(attempted_clauses)

    attempted_clauses_info =
      if attempted_clauses_count > 0 do
        attempted_clauses_list =
          Enum.map_join(attempted_clauses, "\n", fn attempted_clause ->
            "    #{attempted_clause}"
          end)

        """

        Attempted function clauses (showing #{attempted_clauses_count} out of #{attempted_clauses_count}):

        #{attempted_clauses_list}
        """
      else
        ""
      end

    """
    no function clause matching in #{fun_name}#{args_info}#{attempted_clauses_info}\
    """
  end

  @doc """
  Builds an error message for UndefinedFunctionError.
  """
  @spec build_undefined_function_error(mfa, list({fun, arity}), boolean) :: String.t()
  def build_undefined_function_error(undefined_mfa, similar_funs \\ [], module_available? \\ true) do
    {module, fun, arity} = undefined_mfa
    module_name = Reflection.module_name(module)

    undefined_mfa_info =
      cond do
        module_available? ->
          "function #{module_name}.#{fun}/#{arity} is undefined or private"

        Version.match?(System.version(), ">= 1.18.0") ->
          "#{build_module_not_available_error(module_name, fun, arity)}. Make sure the module name is correct and has been specified in full (or that an alias has been defined)"

        true ->
          build_module_not_available_error(module_name, fun, arity)
      end

    similar_funs_info =
      if Enum.any?(similar_funs) do
        Enum.reduce(similar_funs, ". Did you mean:\n\n", fn {fun, arity}, acc ->
          "#{acc}      * #{fun}/#{arity}\n"
        end)
      else
        ""
      end

    "#{undefined_mfa_info}#{similar_funs_info}"
  end

  @doc """
  Prevents term typing violations by converting a term to a string and evaluating it back.
  This is useful in tests when you need to bypass compile-time type checking.
  """
  @spec prevent_term_typing_violation(term()) :: term()
  # sobelow_skip ["RCE.CodeModule"]
  def prevent_term_typing_violation(term) do
    term
    |> inspect()
    |> Code.eval_string()
    |> elem(0)
  end

  @doc """
  Returns the given argument.
  It prevents compiler warnings in tests when the given value is not permitted is specific situation.
  """
  @spec wrap_term(any) :: any
  def wrap_term(value) do
    value
  end

  defp build_module_not_available_error(module_name, fun, arity) do
    "function #{module_name}.#{fun}/#{arity} is undefined (module #{module_name} is not available)"
  end
end
