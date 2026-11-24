# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module61 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module62

  attribute :title, :string, optional: true

  relationship :project, Module62, optional: true

  allow :update, when: none(new(project).members)
end
