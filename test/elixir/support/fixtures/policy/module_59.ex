# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module59 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module58
  alias Hologram.Test.Fixtures.Policy.Module60

  attribute :code, :string, max_length: 3, optional: true
  attribute :count, :integer, default: 0
  attribute :handoff, :string, optional: true
  attribute :mark, :string, max_length: 3, optional: true
  attribute :note, :string, optional: true
  attribute :phase, :string, optional: true
  attribute :signer, :string, max_length: 8, optional: true
  attribute :status, :enum, values: [:pending, :approved, :rejected], default: :pending

  relationship :labels, [Module60]
  relationship :project, Module58, optional: true

  role :admin

  allow :read

  allow :update,
    as: :approve,
    only: [status],
    to: :admin,
    when: status == :pending and new(status) == :approved

  allow :update,
    as: :move,
    only: [project],
    to: {:member, project},
    when: has_role(:member, new(project))

  allow :update, only: [code], when: has_role(:member, new(project))
  allow :update, only: [count], when: new(count) <= 10
  allow :update, only: [note], when: new(project.archived) == false
  allow :update, only: [handoff], when: can(:read, new(project))
  allow :update, only: [mark], when: new(updated_at) > updated_at
  allow :update, only: [labels], when: none(label <- new(labels), label.blocked == true)

  allow :update,
    only: [phase, signer],
    when: new(phase) != "signed" or new(signer) != nil
end
