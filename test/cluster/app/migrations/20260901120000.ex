defmodule HologramClusterTests.Migrations.V20260901120000 do
  @moduledoc false

  use Hologram.Migration

  create_entity HologramClusterTests.Entities.User do
    add_attribute :email, :string
  end

  designate_user_entity HologramClusterTests.Entities.User
end
