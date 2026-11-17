defmodule HologramClusterTests.Migrations.V20260814090003 do
  @moduledoc false

  use Hologram.Migration

  change_entity HologramClusterTests.Entities.Item do
    add_relationship :parent, HologramClusterTests.Entities.Item, optional: true
  end
end
