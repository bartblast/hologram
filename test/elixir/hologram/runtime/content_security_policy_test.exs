defmodule Hologram.Runtime.ContentSecurityPolicyTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Runtime.ContentSecurityPolicy

  describe "nonced_elements/0" do
    test "names every element HTML gives a nonce attribute to" do
      assert nonced_elements() == ["link", "script", "style"]
    end
  end

  describe "generate_nonce/0" do
    test "is 16 random bytes in base64" do
      nonce = generate_nonce()

      assert String.length(nonce) == 24
      assert byte_size(Base.decode64!(nonce)) == 16
    end

    test "differs between calls" do
      assert generate_nonce() != generate_nonce()
    end
  end
end
