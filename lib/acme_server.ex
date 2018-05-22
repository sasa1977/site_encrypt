defmodule AcmeServer do
  alias AcmeServer.Account

  def resource_path(request_path, config) do
    path = config.site_uri.path || ""
    size = byte_size(path)

    case request_path do
      <<^path::binary-size(size), rest_path::binary>> -> {:ok, rest_path}
      _ -> :error
    end
  end

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

  def handle(_config, :head, "/new" <> _, _body), do: respond(405, [nonce_header()])

  def handle(_config, :post, "/new-account", body) do
    account = Account.create(client_key(decode_request(body)))
    respond_json(201, [nonce_header()], account)
  end

  def handle(config, :post, "/new-order", body) do
    request = decode_request(body)

    domains =
      request.payload
      |> Map.fetch!("identifiers")
      |> Enum.filter(&(Map.fetch!(&1, "type") == "dns"))
      |> Enum.map(&Map.fetch!(&1, "value"))

    {account, order} = create_order(request, domains)
    order_path = order_path(account.id, order.id)

    respond_json(201, [{"Location", "#{config.site}/order/#{order_path}"}, nonce_header()], %{
      status: order.status,
      expires: expires(),
      identifiers: Enum.map(domains, &%{type: "dns", value: &1}),
      authorizations: ["#{config.site}/authorizations/#{order_path}"],
      finalize: "#{config.site}/finalize/#{order_path}"
    })
  end

  def handle(config, :get, "/authorizations/" <> order_path, _body) do
    {account_id, order_id} = decode_order_path(order_path)
    order = AcmeServer.Account.get_order!(account_id, order_id)

    respond_json(200, %{
      status: order.status,
      identifier: %{type: "dns", value: "localhost"},
      challenges: [http_challenge_data(config, account_id, order)]
    })
  end

  def handle(config, :post, "/challenge/http/" <> order_path, body) do
    request = decode_request(body)
    {account_id, order_id} = decode_order_path(order_path)
    order = AcmeServer.Account.get_order!(account_id, order_id)
    authorizations_url = "#{config.site}/authorizations/#{order_path}"

    AcmeServer.Jobs.start_http_verifier(%{
      dns: config.dns,
      account_id: account_id,
      order: order,
      key_thumbprint: JOSE.JWK.thumbprint(client_key(request))
    })

    respond_json(
      200,
      [nonce_header(), {"Link", "<#{authorizations_url}>;rel=\"up\""}],
      http_challenge_data(config, account_id, order)
    )
  end

  def handle(config, :post, "/finalize/" <> order_path, body) do
    request = decode_request(body)
    csr = request.payload |> Map.fetch!("csr") |> Base.url_decode64!(padding: false)

    {account_id, order_id} = decode_order_path(order_path)
    order = AcmeServer.Account.get_order!(account_id, order_id)

    cert = AcmeServer.Crypto.sign_csr!({account_id, order_id}, csr, order.domains)
    updated_order = %{order | cert: cert}
    AcmeServer.Account.update_order(account_id, updated_order)

    respond_json(200, [nonce_header()], order_data(config, account_id, updated_order))
  end

  def handle(config, :get, "/order/" <> order_path, _body) do
    {account_id, order_id} = decode_order_path(order_path)
    order = AcmeServer.Account.get_order!(account_id, order_id)
    respond_json(200, order_data(config, account_id, order))
  end

  def handle(_config, :get, "/cert/" <> order_path, _body) do
    {account_id, order_id} = decode_order_path(order_path)
    certificate = AcmeServer.Account.get_order!(account_id, order_id).cert
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

  defp nonce_header(),
    do: {"Replay-Nonce", AcmeServer.Nonce.new() |> to_string() |> Base.encode64(padding: false)}

  defp decode_request(body) do
    {:ok, request} = AcmeServer.JWS.decode(body)
    verify_nonce(request)
    request
  end

  defp client_key(request), do: Map.fetch!(request.protected, "jwk")

  defp verify_nonce(request) do
    nonce =
      request.protected
      |> Map.fetch!("nonce")
      |> Base.decode64!(padding: false)
      |> String.to_integer()

    AcmeServer.Nonce.verify(nonce)
  end

  defp decode_order_path(order_path) do
    [account_id, order_id] = String.split(order_path, "/")
    {String.to_integer(account_id), String.to_integer(order_id)}
  end

  defp create_order(request, domains) do
    account =
      case Account.fetch(client_key(request)) do
        {:ok, account} -> account
        :error -> Account.create(client_key(request))
      end

    {account, AcmeServer.Account.new_order(account, domains)}
  end
end
