defmodule HologramFeatureTests.Middleware.Group do
  use Hologram.Middleware

  middleware HologramFeatureTests.Middleware.SharedStep
  middleware :group_step

  def group_step(server, _opts) do
    put_stash(server, :group, "group step")
  end
end
