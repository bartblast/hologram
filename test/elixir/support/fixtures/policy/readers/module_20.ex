# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module20 do
  use Hologram.Entity

  attribute :archived, :boolean, default: false
  attribute :steward_id, :uuid, optional: true

  allow :update
end
