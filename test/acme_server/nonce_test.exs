defmodule AcmeServer.NonceTest do
  use ExUnit.Case, async: true

  test "new is unique" do
    first_nonce = AcmeServer.Nonce.new()
    nonce = AcmeServer.Nonce.new()
    assert nonce != first_nonce
  end

  test "verify created nonce" do
    nonce = AcmeServer.Nonce.new()
    assert :ok == AcmeServer.Nonce.verify(nonce)
  end

  test "verify created nonce ONLY once" do
    nonce = AcmeServer.Nonce.new()
    assert :ok == AcmeServer.Nonce.verify(nonce)

    assert_raise MatchError, fn ->
      AcmeServer.Nonce.verify(nonce)
    end
  end

  test "verify unknown nonce throw error" do
    assert_raise MatchError, fn ->
      AcmeServer.Nonce.verify(-1)
    end
  end
end
