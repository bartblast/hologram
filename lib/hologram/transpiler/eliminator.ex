defmodule Hologram.Transpiler.Eliminator do
  alias Hologram.Transpiler.AST.{Function, Module}

  @hologram_backend_functions [render: 0]

  def eliminate_dead_code(%Module{functions: functions} = module) do
    preserved_functions =
      Enum.reject(functions, fn %Function{name: name, arity: arity} ->
        if @hologram_backend_functions[name] == arity, do: true, else: false
      end)

    %{module | functions: preserved_functions}
  end
end
