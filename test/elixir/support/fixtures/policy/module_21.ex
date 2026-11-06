# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module21 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module20

  attribute :name, :string, optional: true

  relationship :tasks, [Module20], inverse: tags

  allow :read, when: any(task <- tasks, task.subject == "open")
end
