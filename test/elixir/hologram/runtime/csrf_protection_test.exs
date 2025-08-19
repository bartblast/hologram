defmodule Hologram.Runtime.CSRFProtectionTest do
  use ExUnit.Case, async: true
  import Hologram.Runtime.CSRFProtection

  @csrf_token_session_key "hologram_csrf_token"

  describe "ensure_session_token/1" do
    test "when there is no token in the session, generates and stores a new token" do
      conn = Plug.Test.init_test_session(%Plug.Conn{}, %{})

      updated_conn = ensure_session_token(conn)

      # Should have a token in the session
      session_csrf_token = Plug.Conn.get_session(updated_conn, @csrf_token_session_key)
      assert is_binary(session_csrf_token)
      assert byte_size(session_csrf_token) == 24

      # Should be a valid unmasked token
      masked_token = get_masked_token(session_csrf_token)
      assert validate_token(session_csrf_token, masked_token)
    end

    test "when there is already a token in the session, does nothing" do
      conn = Plug.Test.init_test_session(%Plug.Conn{}, %{})

      # First, ensure a token exists
      conn_with_token = ensure_session_token(conn)
      original_token = Plug.Conn.get_session(conn_with_token, @csrf_token_session_key)

      # Call ensure_session_token again
      updated_conn = ensure_session_token(conn_with_token)

      # Should have the same token
      current_token = Plug.Conn.get_session(updated_conn, @csrf_token_session_key)
      assert current_token == original_token
    end
  end

  describe "generate_tokens/0" do
    test "returns a tuple with masked and unmasked tokens" do
      {masked, unmasked} = generate_tokens()

      assert is_binary(masked)
      assert is_binary(unmasked)
      assert byte_size(unmasked) == 24
      assert byte_size(masked) > 24
    end

    test "generates different tokens each time" do
      {masked_1, unmasked_1} = generate_tokens()
      {masked_2, unmasked_2} = generate_tokens()

      assert masked_1 != masked_2
      assert unmasked_1 != unmasked_2
    end
  end

  describe "generate_unmasked_token/0" do
    test "returns an unmasked token" do
      token = generate_unmasked_token()

      assert is_binary(token)
      assert byte_size(token) == 24
    end

    test "generates different tokens each time" do
      token_1 = generate_unmasked_token()
      token_2 = generate_unmasked_token()

      assert token_1 != token_2
    end
  end

  describe "get_masked_token/1" do
    test "masks an unmasked token" do
      unmasked = generate_unmasked_token()
      masked = get_masked_token(unmasked)

      assert is_binary(masked)
      assert byte_size(masked) > byte_size(unmasked)

      # Should validate correctly
      assert validate_token(unmasked, masked)
    end

    test "generates different masked tokens for the same unmasked token" do
      unmasked = generate_unmasked_token()
      masked_1 = get_masked_token(unmasked)
      masked_2 = get_masked_token(unmasked)

      assert masked_1 != masked_2

      # Should validate correctly      
      assert validate_token(unmasked, masked_1)
      assert validate_token(unmasked, masked_2)
    end
  end

  describe "validate_token/2" do
    test "validates correctly generated tokens" do
      {masked, unmasked} = generate_tokens()

      assert validate_token(unmasked, masked)
    end

    test "rejects invalid tokens" do
      refute validate_token("invalid", "also_invalid")
      refute validate_token(nil, nil)
      refute validate_token("", "")
    end

    test "rejects mismatched valid-looking tokens" do
      {_masked_1, unmasked_1} = generate_tokens()
      {masked_2, _unmasked_2} = generate_tokens()

      refute validate_token(unmasked_1, masked_2)
    end

    test "validates tokens from separate generation calls" do
      unmasked = generate_unmasked_token()
      masked = get_masked_token(unmasked)

      assert validate_token(unmasked, masked)
    end
  end

  describe "integration workflow" do
    test "complete workflow from generation to validation" do
      # Step 1: Generate tokens
      {masked_for_client, unmasked_for_session} = generate_tokens()

      # Step 2: Validate (simulating client sending masked token back)
      assert validate_token(unmasked_for_session, masked_for_client)

      # Step 3: Generate a fresh masked token from existing session token
      fresh_masked = get_masked_token(unmasked_for_session)
      assert validate_token(unmasked_for_session, fresh_masked)

      # Step 4: Verify invalid token is rejected
      {other_masked, _other_unmasked} = generate_tokens()
      refute validate_token(unmasked_for_session, other_masked)
    end
  end
end
