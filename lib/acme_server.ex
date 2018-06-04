defmodule AcmeServer do
  alias AcmeServer.Account

  @type site :: String.t()
  @type dns :: %{String.t() => String.t()}
  @type config :: %{site: site, site_uri: URI.t(), dns: dns}
  @type start_opts :: [config: config, endpoint: Supervisor.child_spec()]

  @type method :: :get | :head | :put | :post | :delete
  @type handle_response :: %{status: status, headers: headers, body: body}
  @type status :: pos_integer
  @type headers :: [{String.t(), String.t()}]
  @type body :: binary

  @spec child_spec(start_opts) :: Supervisor.child_spec()
  def child_spec(opts),
    do: %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}, type: :supervisor}

  @spec start_link(start_opts) :: Supervisor.on_start()
  def start_link(opts) do
    # The supervision subtree of an ACME server instance. This supervisor sits
    # in the client app tree, which supports proper shutdown. If this supervisor
    # is stopped, all the processes associated with this ACME server instance
    # are also terminated.
    Supervisor.start_link(
      [
        {AcmeServer.Db, Keyword.fetch!(opts, :config)},
        {AcmeServer.Challenges, Keyword.fetch!(opts, :config)},
        Keyword.fetch!(opts, :endpoint)
      ],
      strategy: :one_for_one
    )
  end

  @spec config(site: site, dns: dns) :: config
  def config(opts) do
    site_uri = opts |> Keyword.fetch!(:site) |> URI.parse()
    opts |> Map.new() |> Map.put(:site_uri, site_uri)
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

  def handle(config, :head, "/new" <> _, _body), do: respond(405, [nonce_header(config)])

  def handle(config, :post, "/new-account", body) do
    account = Account.create(config, client_key(decode_request(config, body)))
    respond_json(201, [nonce_header(config)], account)
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

  def handle(config, :get, "/authorizations/" <> order_path, _body) do
    {account_id, order_id} = decode_order_path(order_path)
    order = AcmeServer.Account.get_order!(config, account_id, order_id)

    respond_json(200, %{
      status: order.status,
      identifier: %{type: "dns", value: "localhost"},
      challenges: [http_challenge_data(config, account_id, order)]
    })
  end

  def handle(config, :post, "/challenge/http/" <> order_path, body) do
    request = decode_request(config, body)
    {account_id, order_id} = decode_order_path(order_path)
    order = AcmeServer.Account.get_order!(config, account_id, order_id)
    authorizations_url = "#{config.site}/authorizations/#{order_path}"

    AcmeServer.Challenges.start_challenge(config, %{
      dns: config.dns,
      account_id: account_id,
      order: order,
      key_thumbprint: JOSE.JWK.thumbprint(client_key(request))
    })

    respond_json(
      200,
      [nonce_header(config), {"Link", "<#{authorizations_url}>;rel=\"up\""}],
      http_challenge_data(config, account_id, order)
    )
  end

  def handle(config, :post, "/finalize/" <> order_path, body) do
    request = decode_request(config, body)
    csr = request.payload |> Map.fetch!("csr") |> Base.url_decode64!(padding: false)

    {account_id, order_id} = decode_order_path(order_path)
    order = AcmeServer.Account.get_order!(config, account_id, order_id)

    cert = AcmeServer.Crypto.sign_csr!({account_id, order_id}, csr, order.domains)
    updated_order = %{order | cert: cert}
    AcmeServer.Account.update_order(config, account_id, updated_order)

    respond_json(200, [nonce_header(config)], order_data(config, account_id, updated_order))
  end

  def handle(config, :get, "/order/" <> order_path, _body) do
    {account_id, order_id} = decode_order_path(order_path)
    order = AcmeServer.Account.get_order!(config, account_id, order_id)
    respond_json(200, order_data(config, account_id, order))
  end

  def handle(config, :get, "/cert/" <> order_path, _body) do
    {account_id, order_id} = decode_order_path(order_path)
    certificate = AcmeServer.Account.get_order!(config, account_id, order_id).cert
    respond(200, [], certificate)
  end

  defp http_challenge_data(config, account_id, order) do
    %{
      type: "http-01",
      status: order.status,
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
    {"Replay-Nonce", AcmeServer.Nonce.new(config) |> to_string() |> Base.encode64(padding: false)}
  end

  defp decode_request(config, body) do
    {:ok, request} = AcmeServer.JWS.decode(body)
    verify_nonce!(config, request)
    request
  end

  defp client_key(request), do: Map.fetch!(request.protected, "jwk")

  defp verify_nonce!(config, request) do
    nonce =
      request.protected
      |> Map.fetch!("nonce")
      |> Base.decode64!(padding: false)
      |> String.to_integer()

    AcmeServer.Nonce.verify!(config, nonce)
  end

  defp decode_order_path(order_path) do
    [account_id, order_id] = String.split(order_path, "/")
    {String.to_integer(account_id), String.to_integer(order_id)}
  end

  defp create_order(config, request, domains) do
    account =
      case Account.fetch(config, client_key(request)) do
        {:ok, account} -> account
        :error -> Account.create(config, client_key(request))
      end

    {account, AcmeServer.Account.new_order(config, account, domains)}
  end
end
