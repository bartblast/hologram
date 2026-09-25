# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DynamicCallGate.Module1 do
  alias Hologram.Test.Fixtures.Compiler.DynamicCallGate.Module2

  # Calls __struct__/0 on its parameter.
  def build(module), do: module.__struct__()

  # Calls __struct__/0 on its parameter when it is an atom, and gives it back otherwise.
  def build_or_keep(value) when is_atom(value), do: value.__struct__()

  def build_or_keep(value), do: value

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

  def with_map_literal, do: build_or_keep(%{field: :value})

  def with_rescued(fun) do
    fun.()
  rescue
    error -> build_or_keep(error)
  end

  def with_state_value_kept(component), do: build_or_keep(component.state.module)
end
