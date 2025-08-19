defmodule Hologram.Runtime.CSRFProtection do
  @moduledoc false

  @csrf_token_session_key "hologram_csrf_token"

  # Use the same constants as Plug.CSRFProtection for compatibility
  @token_size 18

  @doc """
  Ensures that a CSRF token exists in the session.
  """
  @spec ensure_session_token(Plug.Conn.t()) :: Plug.Conn.t()
  def ensure_session_token(conn) do
    case Plug.Conn.get_session(conn, @csrf_token_session_key) do
      nil ->
        {_masked_token, unmasked_token} = generate_tokens()
        Plug.Conn.put_session(conn, @csrf_token_session_key, unmasked_token)

      _unmasked_token ->
        conn
    end
  end

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
    Base.url_encode64(:crypto.strong_rand_bytes(@token_size))
  end

  @doc """
  Generates a masked CSRF token for client use from an unmasked token.
  """
  @spec get_masked_token(String.t()) :: String.t()
  def get_masked_token(unmasked_token) do
    mask = generate_unmasked_token()

    # Use the same masking algorithm as Plug.CSRFProtection
    Base.url_encode64(Plug.Crypto.mask(unmasked_token, mask)) <> mask
  end

  @doc """
  Validates a client-provided CSRF token against the session token.

  Returns `true` if the masked client token is valid for the given session token.
  """
  @spec validate_token(String.t(), String.t()) :: boolean
  defdelegate validate_token(session_token, client_token),
    to: Plug.CSRFProtection,
    as: :valid_state_and_csrf_token?
end
