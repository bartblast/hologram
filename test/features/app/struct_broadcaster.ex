# Broadcasts a struct referenced by no other app code. The module is compiled into
# the app (so the compiler harvests the struct type from this broadcast caller), but
# it must be invoked only from test code, never from client-reachable code or from
# init/3 or command/3, otherwise it silently stops testing the broadcast-caller
# type harvest.
defmodule HologramFeatureTests.StructBroadcaster do
  alias Hologram.Realtime
  alias HologramFeatureTests.StructFixture5

  def broadcast_struct(channel) do
    struct = %StructFixture5{name: "created in broadcast"}

    Realtime.broadcast_action(channel, :put_struct_from_broadcast, struct: struct)
  end
end
