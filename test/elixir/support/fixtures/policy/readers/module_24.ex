# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module24 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module22
  alias Hologram.Test.Fixtures.Policy.Readers.Module23

  relationship :project, Module23, optional: true
  relationship :team, Module22, optional: true

  allow :read, to: {:member, project.team}
  allow :read, to: {:member, team}
  allow :update, to: {:member, team}
end
