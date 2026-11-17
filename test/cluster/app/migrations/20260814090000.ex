defmodule HologramClusterTests.Migrations.V20260814090000 do
  @moduledoc false

  use Hologram.Migration

  create_entity HologramClusterTests.Entities.Item do
    add_attribute :title, :string
  end
end
