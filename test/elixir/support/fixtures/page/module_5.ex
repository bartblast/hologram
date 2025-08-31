defmodule Hologram.Test.Fixtures.Page.Module5 do
  use Hologram.Page

  alias Hologram.Test.Fixtures.Page.Module2
  alias Hologram.UI.Link

  route "/hologram-test-fixtures-runtime-page-module5"

  layout Hologram.Test.Fixtures.Page.Module4
end
