defmodule AcmeClient do
  alias AcmeClient.API
  alias AcmeClient.Crypto

  def new_account(http_pool, directory_url, contacts) do
    account_key = JOSE.JWK.generate_key({:rsa, 2048})
    session = start_session(http_pool, directory_url, account_key)
    {:ok, session} = API.new_account(session, contacts)
    session
  end

  def for_existing_account(http_pool, directory_url, account_key) do
    session = start_session(http_pool, directory_url, account_key)
    {:ok, session} = API.fetch_kid(session)
    session
  end

  def create_certificate(session, config) do
    {:ok, order, session} = API.new_order(session, config.domains)
    {private_key, order, session} = process_new_order(session, order, config)
    {:ok, cert, chain, session} = API.get_cert(session, order)
    {%{privkey: Crypto.private_key_to_pem(private_key), cert: cert, chain: chain}, session}
  end

  defp start_session(http_pool, directory_url, account_key) do
    {:ok, session} = API.new_session(http_pool, directory_url, account_key)
    {:ok, session} = API.new_nonce(session)
    session
  end

  defp process_new_order(session, %{status: :pending} = order, config) do
    {pending_authorizations, session} =
      Enum.reduce(
        order.authorizations,
        {[], session},
        fn authorization, {pending_authorizations, session} ->
          case authorize(session, config, authorization) do
            {:pending, session} -> {[authorization | pending_authorizations], session}
            {:valid, session} -> {pending_authorizations, session}
          end
        end
      )

    await_server_challenges(Enum.count(pending_authorizations), config)
    {:ok, session} = poll(session, config, &validate_authorizations(&1, pending_authorizations))

    {order, session} =
      poll(session, config, fn session ->
        case API.order_status(session, order) do
          {:ok, %{status: :ready} = order, session} -> {order, session}
          {:ok, _, session} -> {nil, session}
        end
      end)

    process_new_order(session, order, config)
  end

  defp process_new_order(session, %{status: :ready} = order, config) do
    private_key = Crypto.new_private_key(2048)
    csr = Crypto.csr(private_key, config.domains)

    {:ok, _finalization, session} = API.finalize(session, order, csr)

    {order, session} =
      poll(session, config, fn session ->
        case API.order_status(session, order) do
          {:ok, %{status: :valid} = order, session} -> {order, session}
          {:ok, _, session} -> {nil, session}
        end
      end)

    {private_key, order, session}
  end

  defp authorize(session, config, authorization) do
    {:ok, challenges, session} = API.authorization(session, authorization)

    http_challenge = Enum.find(challenges, &(&1.type == "http-01"))
    false = is_nil(http_challenge)

    case http_challenge.status do
      :pending ->
        key_thumbprint = JOSE.JWK.thumbprint(session.account_key)
        config.register_challenge.(http_challenge.token, key_thumbprint)
        {:ok, _challenge_response, session} = API.challenge(session, http_challenge)
        {:pending, session}

      :valid ->
        {:valid, session}
    end
  end

  defp await_server_challenges(count, config) do
    Stream.repeatedly(config.await_challenge)
    |> Stream.take_while(& &1)
    |> Stream.take(count)
    |> Stream.run()
  end

  defp validate_authorizations(session, []), do: {:ok, session}

  defp validate_authorizations(session, [authorization | other_authorizations]) do
    {:ok, challenges, session} = API.authorization(session, authorization)

    if Enum.any?(challenges, &(&1.status == :valid)),
      do: validate_authorizations(session, other_authorizations),
      else: {nil, session}
  end

  defp poll(session, config, operation) do
    poll(
      session,
      operation,
      Map.get(config, :attempts, 60),
      Map.get(config, :delay, :timer.seconds(1))
    )
  end

  defp poll(session, _operation, 0, _), do: {:error, session}

  defp poll(session, operation, attempt, delay) do
    with {nil, session} <- operation.(session) do
      Process.sleep(delay)
      poll(session, operation, attempt - 1, delay)
    end
  end
end
