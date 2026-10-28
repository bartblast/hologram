defmodule Hologram.Runtime.ContentSecurityPolicy do
  @moduledoc false

  @doc """
  The elements a rendered page stamps with its nonce: the ones a directive of the policy names
  the nonce for. Every element HTML gives a nonce attribute to, until the policy is read.
  """
  # TODO: derive from the directives once the policy module reads the config: "script" when
  # script_src names :nonce, "link" and "style" when style_src does, none when the policy is off.
  @spec nonced_elements() :: [String.t()]
  def nonced_elements do
    ~w(link script style)
  end

  @doc """
  Generates a nonce for one rendered page: 128 bits of randomness in the base64 alphabet a
  Content Security Policy nonce source is written in.

  ## Examples

      iex> generate_nonce()
      "f2KQWpHYuoeTQ1ZlbtX4pA=="
  """
  @spec generate_nonce() :: String.t()
  def generate_nonce do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode64()
  end
end
