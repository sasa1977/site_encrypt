defmodule SiteEncrypt.Acme.Client.API do
  @moduledoc """
  Low level API for interacting with an ACME CA server.

  This module is a very incomplete implementation of the ACME client, as described in
  [RFC8555](https://tools.ietf.org/html/rfc8555). Internally, the module uses `Mint.HTTP` to
  communicate with the server. All functions will internally make a blocking HTTP request to
  the server. Therefore it's advised to invoke the functions of this module from within a separate
  process, powered by `Task`.

  To use the client, you first need to create the session with `new_session/3`. Then you can
  interact with the server using the remaining functions of this module. The session doesn't hold
  any resources open, so you can safely use it from multiple processes.
  """
  alias SiteEncrypt.HttpClient
  alias SiteEncrypt.HttpClient
  alias SiteEncrypt.Acme.Client.Crypto

  defmodule Session do
    @moduledoc false
    defstruct ~w/http_opts account_key kid directory nonce/a

    defimpl Inspect do
      def inspect(session, _opts), do: "##{inspect(session.__struct__)}<#{session.directory.url}>"
    end
  end

  @type session :: %Session{
          http_opts: Keyword.t(),
          account_key: JOSE.JWK.t(),
          kid: nil | String.t(),
          directory: nil | directory,
          nonce: nil | String.t()
        }

  @type directory :: %{
          url: String.t(),
          key_change: String.t(),
          new_account: String.t(),
          new_nonce: String.t(),
          new_order: String.t(),
          revoke_cert: String.t()
        }

  @type error :: Mint.Types.error() | HTTP.response()

  @type order :: %{
          :status => status,
          :authorizations => [String.t()],
          :finalize => String.t(),
          :location => String.t(),
          optional(:certificate) => String.t()
        }

  @type challenge :: %{
          :status => status,
          :type => String.t(),
          :url => String.t(),
          optional(:token) => String.t()
        }

  @type status :: :invalid | :pending | :ready | :processing | :valid

  @type session_opts :: [verify_server_cert: boolean]

  @doc """
  Creates a new session to the given CA.

  - `directory_url` has to point to the GET directory resource, such as
    https://acme-v02.api.letsencrypt.org/directory or
    https://acme-staging-v02.api.letsencrypt.org/directory
  - `account_key` is the private key of the CA account. If you want to create the new account, you
    need to generate this key yourself, for example with

        JOSE.JWK.generate_key({:rsa, _key_size = 4096})

    Note that this will not create the account. You need to invoke `new_account/2` to do that.
    It is your responsibility to safely store the private key somewhere.

    If you want to access the existing account, you should pass the same key used for the account
    creation. In this case you'll usually need to invoke `fetch_kid/1` to fetch the key identifier
    from the CA server.

  Note that this function will make an in-process GET HTTP request to the given directory URL.
  """
  @spec new_session(String.t(), X509.PrivateKey.t(), session_opts) ::
          {:ok, session} | {:error, error}
  def new_session(directory_url, account_key, http_opts \\ []) do
    with {response, session} <- initialize_session(http_opts, account_key, directory_url),
         :ok <- validate_response(response) do
      directory =
        response.payload
        |> normalize_keys(~w/keyChange newAccount newNonce newOrder revokeCert/)
        |> Map.merge(session.directory)

      {:ok, %Session{session | directory: directory}}
    end
  end

  @doc "Creates the new account at the CA server."
  @spec new_account(session, [String.t()]) :: {:ok, session} | {:error, error}
  def new_account(session, emails) do
    url = session.directory.new_account
    payload = %{"contact" => Enum.map(emails, &"mailto:#{&1}"), "termsOfServiceAgreed" => true}

    with {:ok, response, session} <- jws_request(session, :post, url, :jwk, payload) do
      location = :proplists.get_value("location", response.headers)
      {:ok, %Session{session | kid: location}}
    end
  end

  @doc """
  Obtains the key identifier of the existing account.

  You only need to invoke this function if the session is created using the key of the existing
  account.
  """
  @spec fetch_kid(session) :: {:ok, session} | {:error, error}
  def fetch_kid(session) do
    url = session.directory.new_account
    payload = %{"onlyReturnExisting" => true}

    with {:ok, response, session} <- jws_request(session, :post, url, :jwk, payload) do
      location = :proplists.get_value("location", response.headers)
      {:ok, %Session{session | kid: location}}
    end
  end

  @doc "Creates a new order on the CA server."
  @spec new_order(session, [String.t()]) :: {:ok, order, session} | {:error, error}
  def new_order(session, domains) do
    payload = %{"identifiers" => Enum.map(domains, &%{"type" => "dns", "value" => &1})}

    with {:ok, response, session} <-
           jws_request(session, :post, session.directory.new_order, :kid, payload) do
      location = :proplists.get_value("location", response.headers)

      result =
        response.payload
        |> normalize_keys(~w/authorizations finalize status/)
        |> Map.update!(:status, &parse_status!/1)
        |> Map.put(:location, location)

      {:ok, result, session}
    end
  end

  @doc "Obtains the status of the given order."
  @spec order_status(session, order) :: {:ok, order, session} | {:error, error}
  def order_status(session, order) do
    with {:ok, response, session} <- jws_request(session, :post, order.location, :kid) do
      result =
        response.payload
        |> normalize_keys(~w/authorizations finalize status certificate/)
        |> Map.update!(:status, &parse_status!/1)

      {:ok, Map.merge(order, result), session}
    end
  end

  @doc "Obtains authorization challenges from the CA."
  @spec authorization(session, String.t()) :: {:ok, [challenge], session}
  def authorization(session, authorization) do
    with {:ok, response, session} <- jws_request(session, :post, authorization, :kid) do
      challenges =
        response.payload
        |> Map.fetch!("challenges")
        |> Stream.map(&normalize_keys(&1, ~w/status token type url/))
        |> Enum.map(&Map.update!(&1, :status, fn value -> parse_status!(value) end))

      {:ok, challenges, session}
    end
  end

  @doc "Returns the status and the token of the http-01 challenge."
  @spec challenge(session, challenge) ::
          {:ok, %{status: status, token: String.t()}, session} | {:error, error}
  def challenge(session, challenge) do
    payload = %{}

    with {:ok, response, session} <- jws_request(session, :post, challenge.url, :kid, payload) do
      result =
        response.payload
        |> normalize_keys(~w/status token/)
        |> Map.update!(:status, &parse_status!/1)

      {:ok, result, session}
    end
  end

  @doc "Finalizes the given order."
  @spec finalize(session, order, binary) :: {:ok, %{status: status}, session} | {:error, error}
  def finalize(session, order, csr) do
    payload = %{"csr" => Base.url_encode64(csr, padding: false)}

    with {:ok, response, session} <- jws_request(session, :post, order.finalize, :kid, payload) do
      result =
        response.payload
        |> normalize_keys(~w/status/)
        |> Map.update!(:status, &parse_status!/1)

      {:ok, result, session}
    end
  end

  @doc "Obtains the certificate and chain from a finalized order."
  @spec get_cert(session, order) :: {:ok, String.t(), String.t(), session} | {:error, error}
  def get_cert(session, order) do
    with {:ok, response, session} <- jws_request(session, :post, order.certificate, :kid) do
      [cert | chain] = String.split(response.body, ~r/^\-+END CERTIFICATE\-+$\K/m, parts: 2)
      {:ok, Crypto.normalize_pem(cert), Crypto.normalize_pem(to_string(chain)), session}
    end
  end

  defp initialize_session(http_opts, account_key, directory_url) do
    http_request(
      %Session{
        http_opts: http_opts,
        account_key: account_key,
        directory: %{url: directory_url}
      },
      :get,
      directory_url
    )
  end

  defp jws_request(session, verb, url, id_field, payload \\ "") do
    with {:ok, session} <- get_nonce(session) do
      headers = [{"content-type", "application/jose+json"}]
      body = jws_body(session, url, id_field, payload)
      session = %Session{session | nonce: nil}

      case http_request(session, verb, url, headers: headers, body: body) do
        {%{status: status} = response, session} when status in 200..299 ->
          {:ok, response, session}

        {%{payload: %{"type" => "urn:ietf:params:acme:error:badNonce"}}, session} ->
          jws_request(session, verb, url, id_field, payload)

        {response, session} ->
          {:error, response, session}
      end
    end
  end

  defp get_nonce(%Session{nonce: nil} = session) do
    with {response, session} <- http_request(session, :head, session.directory.new_nonce),
         :ok <- validate_response(response),
         do: {:ok, session}
  end

  defp get_nonce(session), do: {:ok, session}

  defp jws_body(session, url, id_field, payload) do
    protected =
      Map.merge(
        %{"alg" => "RS256", "nonce" => session.nonce, "url" => url},
        id_map(id_field, session)
      )

    plain_text = if payload == "", do: "", else: Jason.encode!(payload)
    {_, signed} = JOSE.JWS.sign(session.account_key, plain_text, protected)
    Jason.encode!(signed)
  end

  defp id_map(:jwk, session) do
    {_modules, public_map} = JOSE.JWK.to_public_map(session.account_key)
    %{"jwk" => public_map}
  end

  defp id_map(:kid, session), do: %{"kid" => session.kid}

  defp http_request(session, verb, url, opts \\ []) do
    opts =
      opts
      |> Keyword.put_new(:headers, [])
      |> Keyword.update!(:headers, &[{"user-agent", "site_encrypt native client"} | &1])
      |> Keyword.merge(session.http_opts)

    response = HttpClient.request(verb, url, opts)

    content_type = :proplists.get_value("content-type", response.headers, "")

    payload =
      if String.starts_with?(content_type, "application/json") or
           String.starts_with?(content_type, "application/problem+json"),
         do: Jason.decode!(response.body)

    session =
      case Enum.find(response.headers, &match?({"replay-nonce", _nonce}, &1)) do
        {"replay-nonce", nonce} -> %Session{session | nonce: nonce}
        nil -> session
      end

    {Map.put(response, :payload, payload), session}
  end

  defp parse_status!("invalid"), do: :invalid
  defp parse_status!("pending"), do: :pending
  defp parse_status!("ready"), do: :ready
  defp parse_status!("processing"), do: :processing
  defp parse_status!("valid"), do: :valid

  defp normalize_keys(map, allowed_keys) do
    map
    |> Map.take(allowed_keys)
    |> Enum.into(%{}, fn {key, value} ->
      {key |> Macro.underscore() |> String.to_atom(), value}
    end)
  end

  defp validate_response(response),
    do: if(response.status in 200..299, do: :ok, else: {:error, response})
end
