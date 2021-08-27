defmodule Hologram.Compiler.FunctionCallGenerator do
  import Hologram.Compiler.Encoder.Commons
  
  alias Hologram.Compiler.{Context, Generator, Helpers, Opts}
  alias Hologram.Compiler.IR.Variable

  def generate(module, function, params, %Context{} = context, %Opts{} = opts) do
    class = Helpers.class_name(module)
    function = encode_function_name(function)

    params =
      Enum.map(params, fn param ->
        case param do
          %Variable{name: name} ->
            name

          _ ->
            Generator.generate(param, context, opts)
        end
      end)
      |> Enum.join(", ")

    "#{class}.#{function}(#{params})"
  end
end
