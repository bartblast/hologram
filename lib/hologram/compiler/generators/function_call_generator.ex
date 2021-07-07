defmodule Hologram.Compiler.FunctionCallGenerator do
  alias Hologram.Compiler.{Context, Generator, Helpers}
  alias Hologram.Compiler.IR.Variable

  def generate(module, function, params, %Context{} = context) do
    class = Helpers.class_name(module)

    params =
      Enum.map(params, fn param ->
        case param do
          %Variable{name: name} ->
            name

          _ ->
            Generator.generate(param, context)
        end
      end)
      |> Enum.join(", ")

    "#{class}.#{function}(#{params})"
  end
end
