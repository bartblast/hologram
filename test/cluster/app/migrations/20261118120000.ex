defmodule HologramClusterTests.Migrations.V20261118120000 do
  @moduledoc false

  use Hologram.Migration

  change_entity HologramClusterTests.Entities.Item do
    rename_relationship :parent, :container
  end
end
