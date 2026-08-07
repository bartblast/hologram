defmodule Hologram.Commons.TestUtils do
  @moduledoc false

  alias Hologram.Commons.IntegerUtils
  alias Hologram.Commons.KernelUtils
  alias Hologram.Commons.StringUtils
  alias Hologram.Reflection

  defdelegate pid(str), to: IEx.Helpers
  defdelegate port(str), to: IEx.Helpers
  defdelegate ref(str), to: IEx.Helpers

  @doc """
  Builds an error message for ArgumentError.
  """
  @spec build_argument_error_msg(integer(), String.t()) :: String.t()
  def build_argument_error_msg(arg_idx, blame) do
    build_multi_argument_error_msg([{arg_idx, blame}])
  end

  # Keep this message in sync with buildBadArityErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for BadArityError.
  """
  @spec build_bad_arity_error_msg(fun, list) :: String.t()
  def build_bad_arity_error_msg(fun, args) do
    {:arity, arity} = Function.info(fun, :arity)

    count =
      if Enum.empty?(args) do
        "no arguments"
      else
        inspected_args = Enum.map_join(args, ", ", &KernelUtils.inspect/1)
        noun = if length(args) == 1, do: "argument", else: "arguments"

        "#{length(args)} #{noun} (#{inspected_args})"
      end

    "#{KernelUtils.inspect(fun)} with arity #{arity} called with #{count}"
  end

  # Keep this message in sync with buildBadFunctionErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for BadFunctionError.
  """
  @spec build_bad_function_error_msg(any) :: String.t()
  def build_bad_function_error_msg(term) do
    "expected a function, got: " <> KernelUtils.inspect(term)
  end

  # Keep this message in sync with buildBadMapErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for BadMapError.
  """
  @spec build_bad_map_error_msg(any) :: String.t()
  def build_bad_map_error_msg(term) do
    build_value_error_msg("expected a map, got", term)
  end

  # Keep this message in sync with buildCaseClauseErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for CaseClauseError.
  """
  @spec build_case_clause_error_msg(any) :: String.t()
  def build_case_clause_error_msg(term) do
    build_value_error_msg("no case clause matching", term)
  end

  # Keep this message in sync with buildErlangErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for ErlangError.
  """
  @spec build_erlang_error_msg(String.t()) :: String.t()
  def build_erlang_error_msg(blame) do
    "Erlang error: #{blame}"
  end

  # Keep this message in sync with buildFunctionClauseErrorMsg in test/javascript/support/helpers.mjs.
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
          StringUtils.normalize_newlines("""
          #{acc}
              # #{idx + 1}
              #{KernelUtils.inspect(arg)}
          """)
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

    StringUtils.normalize_newlines("""
    no function clause matching in #{fun_name}#{args_info}#{attempted_clauses_info}\
    """)
  end

  # Keep this message in sync with buildKeyErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for KeyError.

  Produces the running Elixir version's format - the inspected value moved onto its
  own indented line as of Elixir 1.19.
  """
  @spec build_key_error_msg(any, map) :: String.t()
  def build_key_error_msg(key, map) do
    inspected_key = KernelUtils.inspect(key)
    inspected_map = KernelUtils.inspect(map)

    if Version.match?(System.version(), ">= 1.19.0") do
      "key #{inspected_key} not found in:\n\n    #{inspected_map}\n"
    else
      "key #{inspected_key} not found in: #{inspected_map}"
    end
  end

  # Keep this message in sync with buildMatchErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for MatchError.
  """
  @spec build_match_error_msg(term) :: String.t()
  def build_match_error_msg(right) do
    build_value_error_msg("no match of right hand side value", right)
  end

  defp build_module_not_available_error(module_name, fun, arity) do
    "function #{module_name}.#{fun}/#{arity} is undefined (module #{module_name} is not available)"
  end

  # Keep this message in sync with buildMultiArgumentErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for ArgumentError with a bullet per erroneous argument.
  """
  @spec build_multi_argument_error_msg(list({integer(), String.t()})) :: String.t()
  def build_multi_argument_error_msg(entries) do
    bullets =
      Enum.map_join(entries, fn {arg_idx, blame} ->
        "  * #{IntegerUtils.ordinal(arg_idx)} argument: #{blame}\n"
      end)

    StringUtils.normalize_newlines("""
    errors were found at the given arguments:

    #{bullets}\
    """)
  end

  # Keep this message in sync with buildTryClauseErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for TryClauseError.
  """
  @spec build_try_clause_error_msg(any) :: String.t()
  def build_try_clause_error_msg(term) do
    build_value_error_msg("no try clause matching", term)
  end

  # Keep this message in sync with buildUndefinedFunctionErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for UndefinedFunctionError.
  """
  @spec build_undefined_function_error_msg(mfa, list({fun, arity}), boolean) :: String.t()
  def build_undefined_function_error_msg(
        undefined_mfa,
        similar_funs \\ [],
        module_available? \\ true
      ) do
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
        indent = if Version.match?(System.version(), ">= 1.19.0"), do: "    ", else: "      "

        Enum.reduce(similar_funs, ". Did you mean:\n\n", fn {fun, arity}, acc ->
          "#{acc}#{indent}* #{fun}/#{arity}\n"
        end)
      else
        ""
      end

    "#{undefined_mfa_info}#{similar_funs_info}"
  end

  # The inspected value moved onto its own indented line as of Elixir 1.19; earlier versions
  # keep it inline. The newest (multi-line) form is mirrored inline by
  # buildBadMapErrorMsg/buildCaseClauseErrorMsg/buildMatchErrorMsg/buildTryClauseErrorMsg/buildWithClauseErrorMsg
  # in assets/js/interpreter.mjs.
  defp build_value_error_msg(label, term) do
    value = KernelUtils.inspect(term)

    if Version.match?(System.version(), ">= 1.19.0") do
      "#{label}:\n\n    #{value}\n"
    else
      "#{label}: #{value}"
    end
  end

  # Keep this message in sync with buildWithClauseErrorMsg in test/javascript/support/helpers.mjs.
  @doc """
  Builds an error message for WithClauseError.
  """
  @spec build_with_clause_error_msg(any) :: String.t()
  def build_with_clause_error_msg(term) do
    build_value_error_msg("no with clause matching", term)
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
end
