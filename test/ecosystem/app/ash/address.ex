defmodule HologramEcosystemTests.Ash.Address do
  use Ash.Resource, data_layer: :embedded

  attributes do
    attribute :street, :string, public?: true
  end
end
