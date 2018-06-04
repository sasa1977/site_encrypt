defmodule AcmeServer.NonceTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  test "new is unique" do
    first_nonce = AcmeServer.Nonce.new()
    nonce = AcmeServer.Nonce.new()
    assert nonce != first_nonce
  end

  test "verify! created nonce" do
    nonce = AcmeServer.Nonce.new()
    assert :ok == AcmeServer.Nonce.verify!(nonce)
  end

  test "verify! created nonce ONLY once" do
    nonce = AcmeServer.Nonce.new()
    assert :ok == AcmeServer.Nonce.verify!(nonce)

    assert_raise MatchError, fn ->
      AcmeServer.Nonce.verify!(nonce)
    end
  end

  test "verify! unknown nonce throw error" do
    assert_raise MatchError, fn ->
      AcmeServer.Nonce.verify!(-1)
    end
  end

  # TODO: Look at adding StreamData.repeatedly to StreamData
  # This code is based on https://elixirforum.com/t/how-to-create-a-custom-streamdata-generator/11935/9
  defp nonce() do
    :ignore
    |> StreamData.constant()
    |> StreamData.bind(fn _ -> StreamData.constant(AcmeServer.Nonce.new()) end)
  end

  property "nonce is always unique" do
    check all nonce_a <- nonce(),
              nonce_b <- nonce() do
      assert nonce_a != nonce_b
    end
  end

  property "nonce is always verifiable" do
    check all nonce_a <- nonce() do
      assert :ok == AcmeServer.Nonce.verify!(nonce_a)
    end
  end

  property "nonce is can only be verified once" do
    check all nonce_a <- nonce() do
      :ok = AcmeServer.Nonce.verify!(nonce_a)

      assert_raise MatchError, fn ->
        AcmeServer.Nonce.verify!(nonce_a)
      end
    end
  end
end
