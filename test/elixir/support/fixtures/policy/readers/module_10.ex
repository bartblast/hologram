# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module10 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Readers.Module9

  attribute :done, :boolean, default: false

  relationship :assignee, Module14, optional: true
  relationship :list, Module9, optional: true
  relationship :reviewer, Module14, optional: true
  relationship :watcher, Module14, optional: true

  allow :read
  allow :read, when: assignee_id == user_id()
end
