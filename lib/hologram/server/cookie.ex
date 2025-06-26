defmodule Hologram.Server.Cookie do
  @moduledoc """
  Represents a cookie to be set in the client's browser.
  """

  defstruct value: nil,
            domain: nil,
            http_only: true,
            max_age: nil,
            path: nil,
            same_site: :lax,
            secure: true

  @type t :: %__MODULE__{
          value: any(),
          domain: String.t() | nil,
          http_only: boolean(),
          max_age: integer() | nil,
          path: String.t() | nil,
          same_site: :lax | :none | :strict,
          secure: boolean()
        }
end
