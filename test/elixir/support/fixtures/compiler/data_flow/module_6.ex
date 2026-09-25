# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Refactor.Apply
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module6 do
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module3
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2

  def apply_fun, do: apply(fn -> %Struct1{} end, [])

  def apply_variable_name(name), do: apply(Module3, name, [])

  def apply_written do
    module = Module3
    apply(module, :build_from, [%Struct2{}])
  end

  # Through apply/3: the type checker takes a dot for map access and rejects a module here.
  def calls_dot_on_param, do: apply(__MODULE__, :dot_on_param, [Struct1])

  def calls_field_of_param, do: field_of_param(%Struct1{field: %Struct2{}})

  def calls_on_param, do: on_param(Module3)

  def dot_on_param(value), do: value.__struct__

  def field do
    struct = %Struct1{field: %Struct2{}}
    struct.field
  end

  def field_of_param(struct), do: struct.field

  def on_literal_module do
    module = Module3
    module.build()
  end

  def on_param(module), do: module.build()

  def struct_module do
    struct = %Struct1{}
    struct.__struct__
  end
end
