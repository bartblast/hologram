defmodule Hologram.Runtime.CSRFProtection do
  @moduledoc false

  @session_key "hologram_csrf_token"

  # Use the same constants as Plug.CSRFProtection for compatibility
  @token_size 18

  @doc """
  Generates both masked and unmasked CSRF tokens.

  Returns `{masked_token, unmasked_token}` where the masked token should be 
  sent to the client and the unmasked token should be stored in the session.
  """
  @spec generate_tokens :: {String.t(), String.t()}
  def generate_tokens do
    unmasked_token = generate_unmasked_token()
    masked_token = get_masked_token(unmasked_token)

    {masked_token, unmasked_token}
  end

  @doc """
  Generates an unmasked CSRF token for session storage.
  """
  @spec generate_unmasked_token :: String.t()
  def generate_unmasked_token do
    # Use the same token generation as Plug.CSRFProtection
    @token_size
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64()
  end

  @doc """
  Generates a masked CSRF token for client use from an unmasked token.
  """
  @spec get_masked_token(String.t()) :: String.t()
  def get_masked_token(unmasked_token) do
    mask = generate_unmasked_token()

    # Use the same masking algorithm as Plug.CSRFProtection
    encoded_masked_token =
      unmasked_token
      |> Plug.Crypto.mask(mask)
      |> Base.url_encode64()

    encoded_masked_token <> mask
  end

  @doc """
  Gets or generates CSRF tokens for the given Plug connection.
  """
  @spec get_or_generate_session_tokens(Plug.Conn.t()) :: {Plug.Conn.t(), {String.t(), String.t()}}
  def get_or_generate_session_tokens(conn) do
    case Plug.Conn.get_session(conn, @session_key) do
      nil ->
        {masked_token, unmasked_token} = generate_tokens()
        updated_conn = Plug.Conn.put_session(conn, @session_key, unmasked_token)
        {updated_conn, {masked_token, unmasked_token}}

      unmasked_token ->
        masked_token = get_masked_token(unmasked_token)
        {conn, {masked_token, unmasked_token}}
    end
  end

  @doc """
  Returns the session key used to store the CSRF token.
  """
  @spec session_key :: String.t()
  def session_key, do: @session_key

  @doc """
  Validates a client-provided CSRF token against the session token.

  Returns `true` if the masked client token is valid for the given session token.
  """
  @spec validate_token(String.t(), String.t()) :: boolean
  defdelegate validate_token(session_token, client_token),
    to: Plug.CSRFProtection,
    as: :valid_state_and_csrf_token?
end
