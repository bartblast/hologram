# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module1 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module2
  alias Hologram.Test.Fixtures.Policy.Readers.Module3

  attribute :name, :string, optional: true

  relationship :members, [Module2], inverse: project
  relationship :milestones, [Module3], inverse: project

  allow :read, when: any(member <- members, member.user_id == user_id())
end
