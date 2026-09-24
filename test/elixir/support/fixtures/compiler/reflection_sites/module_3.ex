# credo:disable-for-this-file Credo.Check.Readability.Specs
# credo:disable-for-this-file Credo.Check.Refactor.Apply
defmodule Hologram.Test.Fixtures.Compiler.ReflectionSites.Module3 do
  alias Hologram.Test.Fixtures.Compiler.ReflectionSites.Module2

  def apply_call(module), do: apply(__MODULE__, :target, [module, []])

  def call_in_anonymous_function(module), do: fn -> target(module, []) end

  def call_of_other_function(module), do: other(module)

  def call_on_rebound_param(module) do
    module = module || Module2
    target(module, [])
  end

  def call_with_state_value(component), do: target(component.state.module, [])

  def calls_repeated(module), do: {target(module, []), target(Module2, [])}

  def local_call(module), do: target(module, [])

  def other(module), do: module

  def remote_call(fields), do: __MODULE__.target(Module2, fields)

  def target(module, fields), do: {module, fields}
end
