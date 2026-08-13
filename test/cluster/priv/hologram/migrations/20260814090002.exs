use Hologram.Migration

change_entity HologramClusterTests.Entities.Item do
  change_attribute :slug, optional: false
end
