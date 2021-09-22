defmodule Hologram.E2E.Web.ErrorView do
  use Hologram.E2E.Web, :view

  def template_not_found(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
