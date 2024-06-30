defmodule SiteEncrypt.Acme.Client do
  @moduledoc """
  ACME related functions for endpoints managed by `SiteEncrypt`.

  This module exposes higher-level ACME client-side scenarios, such as new account creation, and
  certification. Normally these functions are invoked automatically by `SiteEncrypt` processes.

  The functions in this module operate on a running endpoint managed by `SiteEncrypt`. For Phoenix
  this means that the endpoint must be started through `SiteEncrypt.Phoenix`.

  See also `SiteEncrypt.Acme.Client.API` for details about API sessions and lower level API.
  """
  alias SiteEncrypt.Acme.Client.{API, Crypto}

  @doc "Creates the new account."
  @spec new_account(SiteEncrypt.id(), API.session_opts()) :: API.session()
  def new_account(id, session_opts \\ []) do
    config = SiteEncrypt.Registry.config(id)
    account_key = generate_key(config)
    session = start_session(SiteEncrypt.directory_url(config), account_key, session_opts)
    {:ok, session} = API.new_account(session, config.emails)
    session
  end

  @doc "Returns `API` session for the existing account."
  @spec for_existing_account(SiteEncrypt.id(), JOSE.JWK.t(), API.session_opts()) :: API.session()
  def for_existing_account(id, account_key, session_opts) do
    config = SiteEncrypt.Registry.config(id)
    session = start_session(SiteEncrypt.directory_url(config), account_key, session_opts)
    {:ok, session} = API.fetch_kid(session)
    session
  end

  @doc """
  Obtains the new certificate.

  The obtained certificate will not be applied to the endpoint or stored to disk. If you want to
  apply the new certificate to the endpoint, you can pass the returned pems to the function
  `SiteEncrypt.set_certificate/2`.
  """
  @spec create_certificate(API.session(), SiteEncrypt.id()) :: {SiteEncrypt.pems(), API.session()}
  def create_certificate(session, id) do
    config = SiteEncrypt.Registry.config(id)
    {:ok, order, session} = API.new_order(session, config.domains)
    {private_key, order, session} = process_new_order(session, order, config)
    {:ok, cert, chain, session} = API.get_cert(session, order)
    {%{privkey: Crypto.private_key_to_pem(private_key), cert: cert, chain: chain}, session}
  end

  defp generate_key(%{key_type: :rsa, key_size: key_size}) do
    JOSE.JWK.generate_key({:rsa, key_size})
  end

  defp generate_key(%{key_type: :ecdsa, elliptic_curve: curve}) do
    JOSE.JWK.generate_key({:ec, curve})
  end

  defp start_session(directory_url, account_key, session_opts) do
    {:ok, session} = API.new_session(directory_url, account_key, session_opts)
    session
  end

  defp process_new_order(session, %{status: :pending} = order, config) do
    {pending, session} =
      Enum.reduce(
        order.authorizations,
        {[], session},
        fn authorization, {pending_authorizations, session} ->
          case authorize(session, config, authorization) do
            {:pending, challenge, session} ->
              {[{authorization, challenge} | pending_authorizations], session}

            {:valid, session} ->
              {pending_authorizations, session}
          end
        end
      )

    {pending_authorizations, pending_challenges} = Enum.unzip(pending)
    SiteEncrypt.Registry.await_challenges(config.id, pending_challenges, :timer.minutes(1))

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
    private_key = Crypto.new_private_key(Map.get(config, :key_size, 4096))
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
        SiteEncrypt.Registry.register_challenge(config.id, http_challenge.token, key_thumbprint)
        {:ok, _challenge_response, session} = API.challenge(session, http_challenge)
        {:pending, http_challenge.token, session}

      :valid ->
        {:valid, session}
    end
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
      60,
      if(SiteEncrypt.local_ca?(config), do: 50, else: :timer.seconds(2))
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
