# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module18 do
  use Hologram.Entity

  attribute :reviewed, :boolean, default: false, server_only: true
  attribute :steward_id, :id, optional: true, server_only: true

  allow :read, when: reviewed == true
  allow :read, when: steward_id == user_id()
end
