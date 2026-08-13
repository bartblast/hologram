use Hologram.Migration

change_entity HologramClusterTests.Entities.Item do
  add_attribute :slug, :string, optional: true
end
