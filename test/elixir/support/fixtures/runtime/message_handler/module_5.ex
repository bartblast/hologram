defmodule Hologram.Test.Fixtures.Runtime.MessageHandler.Module5 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-message-handler-module5"

  layout Hologram.Test.Fixtures.Runtime.MessageHandler.Module4

  @impl Page
  def template do
    ~HOLO"page Module5 template"
  end
end
