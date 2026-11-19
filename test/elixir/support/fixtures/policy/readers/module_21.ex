# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module21 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module20

  relationship :project, Module20, optional: true

  allow :read, when: project.archived == false
  allow :read, when: project.steward_id == user_id()
end
