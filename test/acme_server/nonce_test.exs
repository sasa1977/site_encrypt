defmodule AcmeServer.NonceTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import StreamData

  test "new is unique" do
    first_nonce = AcmeServer.Nonce.new()
    nonce = AcmeServer.Nonce.new()
    assert nonce != first_nonce
  end

  test "nonce can be verified" do
    nonce = AcmeServer.Nonce.new()
    assert :ok == AcmeServer.Nonce.verify!(nonce)
  end

  test "nonce can be verified only once" do
    nonce = AcmeServer.Nonce.new()
    assert :ok == AcmeServer.Nonce.verify!(nonce)
    assert_raise MatchError, fn -> AcmeServer.Nonce.verify!(nonce) end
  end

  test "unknown nonce isn't verified" do
    assert_raise MatchError, fn -> AcmeServer.Nonce.verify!(:unknown_nonce) end
  end

  property "nonce is always unique" do
    check all nonces <- nonempty(list_of(nonce())) do
      assert Enum.uniq(nonces) == nonces
    end
  end

  property "nonce is always verifiable" do
    check all nonce <- nonce() do
      assert :ok == AcmeServer.Nonce.verify!(nonce)
    end
  end

  property "nonce can only be verified once" do
    check all nonce <- nonce() do
      :ok = AcmeServer.Nonce.verify!(nonce)
      assert_raise MatchError, fn -> AcmeServer.Nonce.verify!(nonce) end
    end
  end

  defp nonce() do
    # we need to map a constant to ensure we get a different nonce every time
    unshrinkable(map(constant(:ignore), fn _ -> AcmeServer.Nonce.new() end))
  end
end
