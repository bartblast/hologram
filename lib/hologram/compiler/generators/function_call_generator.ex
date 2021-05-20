defmodule Hologram.Compiler.FunctionCallGenerator do
  alias Hologram.Compiler.IR.Variable
  alias Hologram.Compiler.Generator
  alias Hologram.Compiler.Helpers

  def generate(module, function, params, context) do
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
