# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Refactor.Apply
defmodule Hologram.Test.Fixtures.Compiler.ReflectionSites.Module1 do
  alias Hologram.Test.Fixtures.Compiler.ReflectionSites.Module2

  def apply_with_function_name(module), do: apply(module, :__schema__, [:fields])

  def apply_with_function_name_and_variable_args(module, args),
    do: apply(module, :__schema__, args)

  def apply_with_variable_function_name(module, function), do: apply(module, function, [])

  def call_in_anonymous_function(module), do: fn -> module.__changeset__() end

  def call_of_other_function(module), do: module.other_fun()

  def call_on_literal_module, do: Module2.__changeset__()

  def call_on_param(_other, module), do: module.__changeset__()

  def call_on_rebound_param(module) do
    module = module || Module2
    module.__changeset__()
  end

  def call_on_state_value(component), do: component.state.schema.__changeset__()

  def calls_repeated(module), do: {module.__changeset__(), module.__changeset__()}

  def dot_on_param(module), do: module.__struct__

  def dot_with_schema_name(module), do: module.__schema__

  def make_fun_with_variable_function_name(module, function),
    do: :erlang.make_fun(module, function, 0)

  def no_calls, do: :ok

  def schema_call_with_2_args(module, field), do: module.__schema__(:type, field)

  def struct_call_with_fields(module, fields), do: module.__struct__(fields)
end
