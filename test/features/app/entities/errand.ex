defmodule HologramFeatureTests.Entities.Errand do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Squad

  attribute :archived, :boolean, default: false
  attribute :status, :enum, values: [:pending, :approved, :rejected], default: :pending
  attribute :title, :string

  relationship :squad, Squad

  allow :read

  allow :update,
    as: :approve,
    only: [:status],
    when: status == :pending and new(status) == :approved

  allow :update, as: :archive, only: [:archived], when: new(archived) == true

  allow :update,
    as: :move,
    only: [:squad],
    to: {:member, squad},
    when: has_role(:member, new(squad))
end
