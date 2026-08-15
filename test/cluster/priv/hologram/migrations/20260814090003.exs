use Hologram.Migration

change_entity HologramClusterTests.Entities.Item do
  add_relationship :parent, HologramClusterTests.Entities.Item, optional: true
end
