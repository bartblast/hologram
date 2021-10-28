alias Hologram.Compiler.Reflection

defmodule Hologram.Compiler.Traverser.Commons do
  def maybe_add_module_def(map, module) do
    unless map[module] || Reflection.standard_lib?(module) do
      module_def = Reflection.module_definition(module)
      Map.put(map, module, module_def)
    else
      map
    end
  end
end
