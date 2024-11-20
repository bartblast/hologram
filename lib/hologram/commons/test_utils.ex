defmodule Hologram.Commons.TestUtils do
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
      if module_available? do
        "function #{module_name}.#{fun}/#{arity} is undefined or private"
      else
        "function #{module_name}.#{fun}/#{arity} is undefined (module #{module_name} is not available)"
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
  Returns the given argument.
  It prevents compiler warnings in tests when the given value is not permitted is specific situation.
  """
  @spec wrap_term(any) :: any
  def wrap_term(value) do
    value
  end
end
