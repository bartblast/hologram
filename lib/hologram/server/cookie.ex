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
            secure: true,
            __meta__: %{node: nil, source: :server, timestamp: nil}

  @type t :: %__MODULE__{
          value: any(),
          domain: String.t() | nil | :unknown,
          http_only: boolean() | :unknown,
          max_age: integer() | nil | :unknown,
          path: String.t() | nil | :unknown,
          same_site: :lax | :none | :strict | :unknown,
          secure: boolean() | :unknown,
          __meta__: %{node: node | nil, source: :client | :server, timestamp: integer | nil}
        }
end
