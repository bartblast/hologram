# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.DataFlow.Module13 do
  alias Hologram.Component
  alias Hologram.Realtime
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Module11
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct1
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct2
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct3
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct4
  alias Hologram.Test.Fixtures.Compiler.DataFlow.Struct5

  def broadcast_component(channel) do
    Realtime.broadcast_action(channel, :put_component, component: Module11)
  end

  def broadcast_except(identity) do
    Realtime.broadcast_action_except(identity, :channel, :put_struct, struct: %Struct5{})
  end

  def broadcast_from_param(channel, params), do: Realtime.broadcast_action(channel, :put, params)

  def broadcast_in_closure(channel) do
    Enum.each([1], fn _count ->
      Realtime.broadcast_action(channel, :put_struct, struct: %Struct3{})
    end)
  end

  def broadcast_label(channel) do
    label = describe(%Struct2{field: :label})
    Realtime.broadcast_action(channel, :put_label, label: label)
  end

  def broadcast_struct(channel) do
    Realtime.broadcast_action(channel, :put_struct, struct: %Struct1{})
    :ok
  end

  def broadcast_without_params(channel), do: Realtime.broadcast_action(channel, :ping)

  def queue_broadcast(server) do
    Component.put_broadcast(server, :channel, :put_struct, struct: %Struct4{})
  end

  defp describe(struct), do: "#{struct.field}"
end
