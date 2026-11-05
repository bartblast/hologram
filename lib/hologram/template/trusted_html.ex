defmodule Hologram.Template.TrustedHTML do
  @moduledoc """
  HTML a template outputs as markup instead of escaping it. Build it with
  `Hologram.Template.trust_html/1`, not directly, so the HTML is always a string.
  """

  @enforce_keys [:html]
  defstruct [:html]

  @type t :: %__MODULE__{html: String.t()}
end
