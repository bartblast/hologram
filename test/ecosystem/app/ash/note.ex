defmodule HologramEcosystemTests.Ash.Note do
  use Ash.Resource,
    domain: HologramEcosystemTests.Ash.Domain,
    data_layer: Ash.DataLayer.Ets

  alias HologramEcosystemTests.Ash.Item

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :text, :string, public?: true
  end

  relationships do
    belongs_to :item, Item, attribute_writable?: true, public?: true
  end

  code_interface do
    define :create
    define :list, action: :read
  end
end
