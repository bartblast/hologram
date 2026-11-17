defmodule HologramClusterTests.Migrations.V20260814090001 do
  @moduledoc false

  use Hologram.Migration

  change_entity HologramClusterTests.Entities.Item do
    add_attribute :slug, :string, optional: true
  end
end
