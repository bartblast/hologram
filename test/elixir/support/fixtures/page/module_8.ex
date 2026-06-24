defmodule Hologram.Test.Fixtures.Page.Module8 do
  use Hologram.Page

  route "/hologram-test-fixtures-runtime-page-module8"

  layout Hologram.Test.Fixtures.Page.Module4

  @impl Page
  def middleware(server) do
    put_status(server, :forbidden)
  end

  @impl Page
  def template do
    ~HOLO"""
    Module8 template
    """
  end
end
