# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module58 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module59

  attribute :archived, :boolean, default: false

  relationship :tasks, [Module59], inverse: project

  role :member

  allow :read
end
