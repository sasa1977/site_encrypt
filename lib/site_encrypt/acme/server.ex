defmodule SiteEncrypt.Acme.Server do
  @moduledoc false
  use Parent.Supervisor
  require Logger
  alias SiteEncrypt.Acme.Server.Account

  @type start_opts :: [id: SiteEncrypt.id(), dns: dns_fun, port: pos_integer()]
  @type config :: %{id: SiteEncrypt.id(), site: String.t(), site_uri: URI.t(), dns: dns_fun}
  @type dns_fun :: (() -> %{String.t() => String.t()})
  @type method :: :get | :head | :put | :post | :delete
  @type handle_response :: %{status: status, headers: headers, body: body}
  @type status :: pos_integer
  @type headers :: [{String.t(), String.t()}]
  @type body :: binary
  @type domains :: [String.t()]

  @spec start_link(term, pos_integer, dns_fun, log_level: Logger.level()) :: Supervisor.on_start()
  def start_link(id, port, dns, opts \\ []) do
    Logger.log(Keyword.get(opts, :log_level, :debug), "Running local ACME server at port #{port}")

    site = "https://localhost:#{port}"

    acme_server_config = %{
      id: id,
      site: site,
      site_uri: URI.parse(site),
      dns: dns
    }

    Parent.Supervisor.start_link([
      {SiteEncrypt.Acme.Server.Db, acme_server_config},
      endpoint_spec(acme_server_config, port)
    ])
  end

  def whereis(id) do
    {:ok, server} = Parent.Client.child_pid(SiteEncrypt.Registry.root(id), __MODULE__)
    server
  end

  @spec resource_path(config, String.t()) :: {:ok, String.t()} | :error
  def resource_path(config, request_path) do
    path = config.site_uri.path || ""
    size = byte_size(path)

    case request_path do
      <<^path::binary-size(size), rest_path::binary>> -> {:ok, rest_path}
      _ -> :error
    end
  end

  @spec handle(config, method, String.t(), binary) :: handle_response
  def handle(config, method, path, body)

  def handle(config, :get, "/directory", _body) do
    respond_json(200, %{
      newNonce: "#{config.site}/new-nonce",
      newAccount: "#{config.site}/new-account",
      newOrder: "#{config.site}/new-order",
      newAuthz: "#{config.site}/new-authz",
      revokeCert: "#{config.site}/revoke-cert",
      keyChange: "#{config.site}/key-change"
    })
  end

  def handle(config, :head, "/new-nonce", _body), do: respond(200, [nonce_header(config)])

  def handle(config, :post, "/new-account", body) do
    request = decode_request(config, body)

    account =
      case Account.fetch(config, client_key(request)) do
        {:ok, account} -> account
        :error -> Account.create(config, client_key(request))
      end

    respond_json(
      201,
      [{"Location", account.location}, nonce_header(config)],
      %{status: :valid, contact: Map.get(request.payload, "contact", [])}
    )
  end

  def handle(config, :post, "/new-order", body) do
    request = decode_request(config, body)

    domains =
      request.payload
      |> Map.fetch!("identifiers")
      |> Enum.filter(&(Map.fetch!(&1, "type") == "dns"))
      |> Enum.map(&Map.fetch!(&1, "value"))

    {account, order} = create_order(config, request, domains)
    order_path = order_path(account.id, order.id)

    respond_json(
      201,
      [{"Location", "#{config.site}/order/#{order_path}"}, nonce_header(config)],
      %{
        status: order.status,
        expires: expires(),
        identifiers: Enum.map(domains, &%{type: "dns", value: &1}),
        authorizations: ["#{config.site}/authorizations/#{order_path}"],
        finalize: "#{config.site}/finalize/#{order_path}"
      }
    )
  end

  def handle(config, :post, "/authorizations/" <> order_path, body) do
    _request = decode_request(config, body)

    {account_id, order_id} = decode_order_path(order_path)
    order = SiteEncrypt.Acme.Server.Account.get_order!(config, account_id, order_id)

    respond_json(
      200,
      [nonce_header(config)],
      %{
        status: with(:ready <- order.status, do: :valid),
        identifier: %{type: "dns", value: "localhost"},
        challenges: [http_challenge_data(config, account_id, order)]
      }
    )
  end

  def handle(config, :post, "/challenge/http/" <> order_path, body) do
    request = decode_request(config, body)
    {account_id, order_id} = decode_order_path(order_path)
    order = SiteEncrypt.Acme.Server.Account.get_order!(config, account_id, order_id)
    authorizations_url = "#{config.site}/authorizations/#{order_path}"

    challenge_data = %{
      dns: config.dns.(),
      account_id: account_id,
      order: order,
      key_thumbprint: JOSE.JWK.thumbprint(client_key(request))
    }

    Parent.Client.start_child(
      whereis(config.id),
      {SiteEncrypt.Acme.Server.Challenge, {config, challenge_data}}
    )

    respond_json(
      200,
      [nonce_header(config), {"Link", "<#{authorizations_url}>;rel=\"up\""}],
      http_challenge_data(config, account_id, order, status: :processing)
    )
  end

  def handle(config, :post, "/finalize/" <> order_path, body) do
    request = decode_request(config, body)
    csr = request.payload |> Map.fetch!("csr") |> Base.url_decode64!(padding: false)

    {account_id, order_id} = decode_order_path(order_path)
    order = SiteEncrypt.Acme.Server.Account.get_order!(config, account_id, order_id)

    cert = SiteEncrypt.Acme.Server.Crypto.sign_csr!(csr, order.domains)
    updated_order = %{order | cert: cert, status: :valid}
    SiteEncrypt.Acme.Server.Account.update_order(config, account_id, updated_order)

    respond_json(200, [nonce_header(config)], order_data(config, account_id, updated_order))
  end

  def handle(config, :post, "/order/" <> order_path, _body) do
    {account_id, order_id} = decode_order_path(order_path)
    order = SiteEncrypt.Acme.Server.Account.get_order!(config, account_id, order_id)
    respond_json(200, [nonce_header(config)], order_data(config, account_id, order))
  end

  def handle(config, :post, "/cert/" <> order_path, body) do
    _ = decode_request(config, body)
    {account_id, order_id} = decode_order_path(order_path)
    certificate = SiteEncrypt.Acme.Server.Account.get_order!(config, account_id, order_id).cert
    respond(200, [nonce_header(config)], certificate)
  end

  defp http_challenge_data(config, account_id, order, opts \\ []) do
    %{
      type: "http-01",
      status: Keyword.get(opts, :status, with(:ready <- order.status, do: :valid)),
      url: "#{config.site}/challenge/http/#{order_path(account_id, order.id)}",
      token: order.token
    }
  end

  defp order_data(config, account_id, order) do
    %{
      status: order.status,
      identifier: %{type: "dns", value: "localhost"},
      certificate: "#{config.site}/cert/#{order_path(account_id, order.id)}"
    }
  end

  defp order_path(account_id, order_id), do: "#{account_id}/#{order_id}"

  defp expires() do
    NaiveDateTime.utc_now()
    |> NaiveDateTime.add(3600, :second)
    |> DateTime.from_naive!("Etc/UTC")
    |> DateTime.to_iso8601()
  end

  defp respond(status, headers, body \\ ""), do: %{status: status, headers: headers, body: body}

  defp respond_json(status, headers \\ [], data),
    do: respond(status, [{"Content-Type", "application/json"} | headers], Jason.encode!(data))

  defp nonce_header(config) do
    {"Replay-Nonce",
     SiteEncrypt.Acme.Server.Nonce.new(config) |> to_string() |> Base.encode64(padding: false)}
  end

  defp decode_request(config, body) do
    {:ok, request} = SiteEncrypt.Acme.Server.JWS.decode(body)
    verify_nonce!(config, request)
    request
  end

  defp client_key(request), do: request.jwk

  defp verify_nonce!(config, request) do
    nonce =
      request.protected
      |> Map.fetch!("nonce")
      |> Base.decode64!(padding: false)
      |> String.to_integer()

    SiteEncrypt.Acme.Server.Nonce.verify!(config, nonce)
  end

  defp decode_order_path(order_path) do
    [account_id, order_id] = String.split(order_path, "/")
    {account_id, String.to_integer(order_id)}
  end

  defp create_order(config, request, domains) do
    account =
      case Account.fetch(config, client_key(request)) do
        {:ok, account} -> account
        :error -> Account.create(config, client_key(request))
      end

    {account, SiteEncrypt.Acme.Server.Account.new_order(config, account, domains)}
  end

  cond do
    Code.ensure_loaded?(Plug.Cowboy) ->
      defp endpoint_spec(config, port) do
        key = X509.PrivateKey.new_rsa(1024)
        cert = X509.Certificate.self_signed(key, "/C=US/ST=CA/O=Acme/CN=ECDSA Root CA")

        adapter_opts = [
          plug: {SiteEncrypt.Acme.Server.Plug, config},
          scheme: :https,
          key: {:PrivateKeyInfo, X509.PrivateKey.to_der(key, wrap: true)},
          cert: X509.Certificate.to_der(cert),
          transport_options: [num_acceptors: 1],
          ref: :"#{__MODULE__}_#{port}",
          options: [port: port]
        ]

        Plug.Cowboy.child_spec(adapter_opts)
      end

    Code.ensure_loaded?(Bandit) ->
      defp endpoint_spec(config, port) do
        key = X509.PrivateKey.new_rsa(1024)
        cert = X509.Certificate.self_signed(key, "/C=US/ST=CA/O=Acme/CN=ECDSA Root CA")

        adapter_opts = [
          plug: {SiteEncrypt.Acme.Server.Plug, config},
          scheme: :https,
          thousand_island_options: [
            num_acceptors: 1,
            port: port,
            transport_options: [
              key: {:PrivateKeyInfo, X509.PrivateKey.to_der(key, wrap: true)},
              cert: X509.Certificate.to_der(cert)
            ]
          ]
        ]

        Bandit.child_spec(adapter_opts)
      end

    true ->
      defp endpoint_spec(config, port) do
        raise """
        missing HTTP server

        Please add either :plug_cowboy or :bandit to your mix.exs :deps list and run:

            mix deps.get
            mix deps.compile --force site_encrypt
        """
      end
  end
end
