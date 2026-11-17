# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Readers.Module19 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Readers.Module18

  relationship :report, Module18, optional: true

  allow :read, when: report.steward_id == user_id()
  allow :read, when: report.reviewed == true or report.steward_id != user_id()
end
