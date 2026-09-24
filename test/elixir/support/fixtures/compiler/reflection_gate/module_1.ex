# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.ReflectionGate.Module1 do
  alias Hologram.Test.Fixtures.Compiler.ReflectionGate.Module2

  # Calls __struct__/0 on its parameter.
  def build(module), do: module.__struct__()

  def capturing, do: Enum.map([Module2], &build/1)

  def forwarding(module), do: build(module)

  def forwarding_with_literal, do: forwarding(Module2)

  def forwarding_with_state_value(component), do: forwarding(component.state.module)

  def no_call, do: :ok

  def recursive(module, 0), do: build(module)

  def recursive(module, count), do: recursive(module, count - 1)

  def recursive_with_literal, do: recursive(Module2, 3)

  def with_literal, do: build(Module2)

  def with_state_value(component), do: build(component.state.module)
end
