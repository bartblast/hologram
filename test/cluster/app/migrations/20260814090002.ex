defmodule HologramClusterTests.Migrations.V20260814090002 do
  @moduledoc false

  use Hologram.Migration

  change_entity HologramClusterTests.Entities.Item do
    change_attribute :slug, optional: false
  end
end
