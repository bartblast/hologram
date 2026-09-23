# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module6 do
  alias Hologram.Realtime
  alias Hologram.Test.Fixtures.Mix.Tasks.Compile.Hologram.Module5

  def notify, do: Realtime.broadcast_action(:room_a, :my_action, component: Module5)
end
