use Hologram.Migration

create_entity HologramClusterTests.Entities.User do
  add_attribute :email, :string
end

designate_user_entity HologramClusterTests.Entities.User
