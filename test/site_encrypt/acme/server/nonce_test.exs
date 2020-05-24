defmodule SiteEncrypt.Acme.Server.NonceTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  import StreamData

  setup do
    [config: start_acme_server()]
  end

  test "new is unique", context do
    first_nonce = SiteEncrypt.Acme.Server.Nonce.new(context.config)
    nonce = SiteEncrypt.Acme.Server.Nonce.new(context.config)
    assert nonce != first_nonce
  end

  test "nonce can be verified", context do
    nonce = SiteEncrypt.Acme.Server.Nonce.new(context.config)
    assert :ok == SiteEncrypt.Acme.Server.Nonce.verify!(context.config, nonce)
  end

  test "nonce can be verified only once", context do
    nonce = SiteEncrypt.Acme.Server.Nonce.new(context.config)
    assert :ok == SiteEncrypt.Acme.Server.Nonce.verify!(context.config, nonce)

    assert_raise MatchError, fn ->
      SiteEncrypt.Acme.Server.Nonce.verify!(context.config, nonce)
    end
  end

  test "unknown nonce isn't verified", context do
    assert_raise MatchError, fn ->
      SiteEncrypt.Acme.Server.Nonce.verify!(context.config, :unknown_nonce)
    end
  end

  property "nonce is always unique", context do
    check all(nonces <- nonempty(list_of(nonce(context.config)))) do
      assert Enum.uniq(nonces) == nonces
    end
  end

  property "nonce is always verifiable", context do
    check all(nonce <- nonce(context.config)) do
      assert :ok == SiteEncrypt.Acme.Server.Nonce.verify!(context.config, nonce)
    end
  end

  property "valid nonce is not verifiable in another server", context do
    another_server_config = start_acme_server()

    check all(nonce <- nonce(context.config)) do
      assert_raise MatchError, fn ->
        SiteEncrypt.Acme.Server.Nonce.verify!(another_server_config, nonce)
      end
    end
  end

  property "nonce can only be verified once", context do
    check all(nonce <- nonce(context.config)) do
      :ok = SiteEncrypt.Acme.Server.Nonce.verify!(context.config, nonce)

      assert_raise MatchError, fn ->
        SiteEncrypt.Acme.Server.Nonce.verify!(context.config, nonce)
      end
    end
  end

  defp nonce(config) do
    # we need to map a constant to ensure we get a different nonce every time
    unshrinkable(map(constant(:ignore), fn _ -> SiteEncrypt.Acme.Server.Nonce.new(config) end))
  end

  defp start_acme_server() do
    url = "http://localhost_#{:erlang.unique_integer([:positive, :monotonic])}"
    config = SiteEncrypt.Acme.Server.config(site: url)
    endpoint = {Agent, fn -> :ok end}
    {:ok, _} = SiteEncrypt.Acme.Server.start_link(config: config, endpoint: endpoint)
    config
  end
end
