defmodule Hologram.E2E.Web.ErrorHelpers do
  use Phoenix.HTML

  def error_tag(form, field) do
    Enum.map(Keyword.get_values(form.errors, field), fn error ->
      content_tag(:span, error,
        class: "invalid-feedback",
        phx_feedback_for: input_name(form, field)
      )
    end)
  end
end
