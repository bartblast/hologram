defmodule Hologram.Session do
  @moduledoc false

  alias Plug.Crypto.KeyGenerator
  alias Plug.Crypto.MessageEncryptor

  @doc """
  Initializes or retrieves an existing session from the "hologram_session" cookie.

  Returns `{conn, session_id}` where:
  - `conn` is the connection with the session cookie set
  - `session_id` is the UUID of the session
  """
  @spec init(Plug.Conn.t()) :: {Plug.Conn.t(), String.t()}
  def init(initial_conn) do
    # This is idempotent
    conn = Plug.Conn.fetch_cookies(initial_conn)

    case conn.req_cookies["hologram_session"] do
      nil ->
        create_new_session(conn)

      encrypted_session ->
        case decrypt_session_data(encrypted_session) do
          {:ok, session_data} ->
            session_id = session_data.session_id
            {conn, session_id}

          {:error, _reason} ->
            create_new_session(conn)
        end
    end
  end

  defp create_new_session(conn) do
    session_id = UUID.uuid4()
    session_data = %{session_id: session_id}
    encrypted_session = encrypt_session_data(session_data)
    new_conn = put_session_cookie(conn, encrypted_session)

    {new_conn, session_id}
  end

  # sobelow_skip ["Misc.BinToTerm"]
  defp decrypt_session_data(encrypted_data) do
    encryption_key = derive_encryption_key()

    # last param (sign key) in encrypt/3 is not used
    case MessageEncryptor.decrypt(encrypted_data, encryption_key, "") do
      {:ok, decrypted_data} ->
        {:ok, :erlang.binary_to_term(decrypted_data)}

      :error ->
        {:error, :invalid_session}
    end
  rescue
    _error -> {:error, :invalid_session}
  end

  defp derive_encryption_key do
    "SECRET_KEY_BASE"
    |> System.fetch_env!()
    |> KeyGenerator.generate("hologram session")
  end

  defp encrypt_session_data(data) do
    serialized_data = :erlang.term_to_binary(data, compressed: 6)
    encryption_key = derive_encryption_key()

    # last param (sign key) in encrypt/3 is not used
    MessageEncryptor.encrypt(serialized_data, encryption_key, "")
  end

  defp put_session_cookie(conn, encrypted_session) do
    Plug.Conn.put_resp_cookie(conn, "hologram_session", encrypted_session,
      http_only: true,
      same_site: "Lax",
      secure: conn.scheme == :https
    )
  end
end
