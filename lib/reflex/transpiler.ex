defmodule Reflex.Transpiler do
  def meta(var) when is_binary(var) do
    {:string, var}
  end

  def meta(var) when is_integer(var) do
    {:integer, var}
  end

  def parse!(str) do
    case Code.string_to_quoted(str) do
      {:ok, ast} ->
        ast

      _ ->
        raise "Invalid code"
    end
  end

  def parse_file(path) do
    path
    |> File.read!()
    |> Code.string_to_quoted()
  end

  def transpile(ast, vars \\ %{})

  def transpile(ast, _vars) when is_binary(ast) do
    ast
  end

  def transpile(ast, _vars) when is_integer(ast) do
    to_string(ast)
  end

  def transpile(ast, _vars) when is_boolean(ast) do
    to_string(ast)
  end

  def transpile({:if, _, [condition, [do: do_branch, else: else_branch]]}, vars) do
    "if (#{transpile(condition, vars)}) { #{transpile(do_branch, vars)} } else { #{transpile(else_branch, vars)} }"
  end
end
