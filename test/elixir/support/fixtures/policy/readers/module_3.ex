# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module3 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module1

  attribute :title, :string, optional: true

  relationship :project, Module1, optional: true

  allow :read, when: any(member <- project.members, member.user_id == user_id())
end
